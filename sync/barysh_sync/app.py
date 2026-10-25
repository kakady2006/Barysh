"""The background loop: watch SavedVariables, import, write Market.lua, report errors."""

import json
import logging
import time
from pathlib import Path

import datetime

from . import backup, db, errors, exports, luadata, market_file, sheets, stats
from .paths import find_game_dirs, market_file as market_path, saved_variables_files

log = logging.getLogger("barysh_sync")


class App:
    def __init__(self, cfg, github=None, clock=time.time, sheets_client=None):
        self.cfg = cfg
        self.clock = clock
        cfg.data_dir.mkdir(parents=True, exist_ok=True)
        self.con = db.connect(cfg.database)
        self.github = github if github is not None else (
            errors.GitHub(cfg.repo_dir) if cfg.github_issues else None)
        self.sheets = sheets_client
        if self.sheets is None and cfg.sheets_enabled:
            from .gauth import ServiceAccount
            self.sheets = sheets.Sheets(cfg.spreadsheet_id, ServiceAccount(cfg.google_key_file))
        self.seen = {}  # path -> (mtime, size) last processed
        self.last = None  # summary of the last sync, for the tray

    def game_dirs(self):
        if self.cfg.game_dir:
            return [self.cfg.game_dir]
        return find_game_dirs()

    def process(self, sv_path, game_dir):
        """Imports one SavedVariables file. Returns a short summary dict."""
        sv_path = Path(sv_path)
        if backup.looks_truncated(sv_path):
            log.warning("Файл %s пустой или обрезан — пропускаю (резервные копии целы)", sv_path)
            return {"skipped": "truncated"}
        backup.make_backup(sv_path, self.cfg.backups)
        text = sv_path.read_text(encoding="latin-1")
        data = luadata.loads(text).get("BaryshDB") or {}

        new_ack = db.import_saved_variables(self.con, data, errors.key_hash)
        ack = db.get_meta(self.con, "ack", {})
        for k, v in new_ack.items():
            ack[k] = max(ack.get(k, 0), v)
        db.set_meta(self.con, "ack", ack)

        now = int(self.clock())
        house_keys = stats.houses(self.con)
        houses = {ah: stats.market_stats(self.con, ah, now) for ah in house_keys}
        series = {ah: stats.daily_series(self.con, ah, now) for ah in house_keys}
        market_file.write(market_path(game_dir), market_file.render(now, ack, houses, series))

        day = datetime.date.fromtimestamp(now).isoformat()
        db.save_capital(self.con, day, now, stats.capital(data.get("chars"), houses))

        made = self.build_exports(data, houses, now)

        pushed = None
        if self.sheets is not None:
            try:
                pushed = sheets.push(self.con, self.sheets, data, houses, db.get_meta, db.set_meta, now)
            except Exception as e:  # the sheet is optional: never stop the sync for it
                log.warning("Google Таблица: не удалось обновить: %s", e)

        sent = 0
        if self.github is not None:
            anon = errors.Anonymizer(errors.names_from_chars(data.get("chars")))
            sent = errors.report_errors(self.con, self.github, anon, log=log.warning)

        summary = {
            "file": str(sv_path), "t": now, "ack": ack, "houses": {k: len(v) for k, v in houses.items()},
            "errors_sent": sent, "exports": len(made), "sheets": pushed,
        }
        self.cfg.status_file.write_text(json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
        log.info("Синхронизировано: %s", summary)
        self.last = summary
        return summary

    def build_exports(self, data, houses, now):
        """Files for "Export for analysis" requests not built yet."""
        done = int(db.get_meta(self.con, "exports_done", 0) or 0)
        made = []
        for req in luadata.as_list(data.get("exportRequests")):
            t = int(req.get("t") or 0)
            if t > done and req.get("ah"):
                path = exports.build(self.con, req, self.cfg.exports, houses, now)
                log.info("Экспорт для анализа: %s", path)
                made.append(path)
                done = max(done, t)
        if made:
            db.set_meta(self.con, "exports_done", done)
        return made

    def changed_files(self):
        """SavedVariables files whose size or time changed since the last processing."""
        out = []
        for game_dir in self.game_dirs():
            for sv in saved_variables_files(game_dir):
                st = sv.stat()
                sig = (st.st_mtime, st.st_size)
                if self.seen.get(sv) != sig:
                    out.append((sv, game_dir, sig))
        return out

    def poll_once(self, settle=0.0):
        done = []
        for sv, game_dir, sig in self.changed_files():
            if settle:
                # The game may still be writing: wait until the file stops changing.
                time.sleep(settle)
                st = sv.stat()
                if (st.st_mtime, st.st_size) != sig:
                    continue
            try:
                done.append(self.process(sv, game_dir))
            except Exception:  # keep running whatever one file does
                log.exception("Ошибка при обработке %s", sv)
            self.seen[sv] = sig
        return done

    def run_forever(self):
        log.info("BaryshSync запущен, папки игры: %s", [str(d) for d in self.game_dirs()] or "не найдены")
        while True:
            self.poll_once(settle=1.0)
            time.sleep(self.cfg.poll_seconds)
