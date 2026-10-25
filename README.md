# Barysh

Аддон аукциона для **World of Warcraft: Forever**: сканирует рынок, считает рыночную цену, скорость продаж и стоимость распыла и показывает выгодные покупки. Каждое действие с золотом или предметом выполняется одним кликом игрока — аддон ничего не покупает и не выставляет сам.

Статус: в разработке, первая проверка в игре — после запуска Forever 5 ноября 2026.

## Состав
- `Barysh/` — аддон.
- `sync/` — BaryshSync: программа для Windows, которая забирает данные аддона после каждого сохранения, ведёт базу SQLite и возвращает аддону рыночную статистику.
- `tests/` — автотесты логики (pytest + lupa, Lua 5.1).
- `docs/` — решения и чек-лист проверки в игре.

## Установка (разработка)
```powershell
powershell -ExecutionPolicy Bypass -File tools\install.ps1 -AddOnsDir "C:\Program Files (x86)\World of Warcraft\_<папка Forever>_\Interface\AddOns"
```
Скрипт делает ссылку на папку `Barysh` и создаёт `Barysh/Data/Market.lua` из заглушки.

## BaryshSync
```powershell
cd sync
python -m barysh_sync            # работает в фоне, следит за сохранениями
python -m barysh_sync --once     # обработать один раз и выйти
powershell -ExecutionPolicy Bypass -File ..\tools\register-sync-task.ps1   # автозапуск при входе в Windows
```
Настройки — `sync/config.toml` (пример: `sync/config.example.toml`, там же — как подключить Google Таблицу). Данные, резервные копии и файлы «Экспорт для анализа» — в `%LOCALAPPDATA%\BaryshSync`. При автозапуске BaryshSync показывает значок в трее с временем последней синхронизации.

Строки импорта списков можно готовить вне игры:
```powershell
python -m barysh_sync encode list.json      # {"list": "stock", "items": {"2589": {"buyBelow": 900, "note": "..."}}}
python -m barysh_sync decode "!BARYSH:1!..."
```

## Команды в игре
`/barysh` — окно, `settings` — настройки, `scan` — полный скан, `quick` — быстрый, `import`, `export [список]`, `probe` — отчёт о клиенте, `save` — сохранить (`/reload`), `de` — показать/скрыть распылитель, `modules`, `module <Имя> on|off`.

Вкладки: Обзор, Сделки, Продажи, Склад, Рынок, Учёт, Почта. Панели у окон игры: почта, профессия (выгода рецептов), обмен; кнопка «Продать торговцу» у торговца.

## Тесты
```powershell
python -m pip install -r requirements-dev.txt
python -m pytest
```

## Лицензия
MIT
