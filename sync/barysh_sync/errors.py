"""Addon errors -> anonymised GitHub issues (one issue per unique error)."""

import hashlib
import re
import subprocess

MARKER = "barysh-error:"


def key_hash(key):
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]


class Anonymizer:
    """Replaces character names and Windows user names with placeholders."""

    def __init__(self, names=()):
        self.map = {}
        for name in sorted({n for n in names if n}, key=len, reverse=True):
            self.add(name)

    def add(self, name):
        if name not in self.map:
            self.map[name] = f"Character{len(self.map) + 1}"

    def __call__(self, text):
        if not text:
            return text
        text = re.sub(r"(?i)([a-z]:[\\/]+users[\\/]+)[^\\/\s]+", r"\1<user>", text)
        text = re.sub(r"(?i)(WTF[\\/]+Account[\\/]+)[^\\/\s]+", r"\1<account>", text)
        for name, alias in self.map.items():
            text = re.sub(re.escape(name), alias, text)
        return text


def names_from_chars(chars):
    """'Name-Realm' keys -> ['Name-Realm', 'Name']"""
    out = []
    for key in chars or {}:
        out.append(key)
        out.append(key.split("-", 1)[0])
    return out


def issue_body(row, anon):
    msg, stack, version, count, first, last, h = row
    return (
        f"Ошибка аддона Barysh (версия {version}), повторов: {count}.\n\n"
        f"```\n{anon(msg)}\n```\n\n<details><summary>Стек</summary>\n\n```\n{anon(stack)}\n```\n</details>\n\n"
        f"<!-- {MARKER}{h} -->\n"
    )


def issue_title(msg, anon):
    first = anon(msg or "").splitlines()[0] if msg else "unknown"
    first = re.sub(r"^Interface[\\/]AddOns[\\/]", "", first)
    return "Addon error: " + (first[:90] + "…" if len(first) > 90 else first)


class GitHub:
    """Talks to GitHub through the gh CLI from the repository folder."""

    def __init__(self, repo_dir, runner=subprocess.run):
        self.repo_dir = repo_dir
        self.run = runner

    def _gh(self, *args, body=None):
        res = self.run(["gh", *args], cwd=self.repo_dir, input=body, capture_output=True, text=True,
                       encoding="utf-8", check=True)
        return res.stdout.strip()

    def create_issue(self, title, body):
        url = self._gh("issue", "create", "--title", title, "--label", "addon-error", "--body-file", "-", body=body)
        return int(url.rstrip("/").rsplit("/", 1)[-1])

    def comment(self, number, body):
        self._gh("issue", "comment", str(number), "--body-file", "-", body=body)

    def ensure_label(self):
        try:
            self._gh("label", "create", "addon-error", "--color", "d73a4a", "--description",
                     "Errors reported automatically by BaryshSync")
        except subprocess.CalledProcessError:
            pass  # already exists


def report_errors(con, github, anon, log=print):
    """Creates issues for new errors and comments when the count grew. Returns how many were sent."""
    rows = con.execute(
        "SELECT msg, stack, version, count, first, last, key_hash, issue, reported_count FROM errors "
        "WHERE count > reported_count").fetchall()
    if not rows:
        return 0
    github.ensure_label()
    sent = 0
    for msg, stack, version, count, first, last, h, issue, reported in rows:
        try:
            if issue is None:
                issue = github.create_issue(issue_title(msg, anon),
                                            issue_body((msg, stack, version, count, first, last, h), anon))
            else:
                github.comment(issue, f"Повтор: всего {count} раз, версия {version}.")
        except (subprocess.CalledProcessError, OSError) as e:
            log(f"GitHub: не удалось отправить ошибку {h}: {e}")
            continue
        con.execute("UPDATE errors SET issue = ?, reported_count = ? WHERE key_hash = ?", (issue, count, h))
        con.commit()
        sent += 1
    return sent
