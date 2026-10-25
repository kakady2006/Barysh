local _, ns = ...

ns.RegisterLocale("ruRU", {
    LOADED = "Barysh %s загружен. Команды: /barysh",
    HELP = "Команды: /barysh modules, /barysh errors, /barysh profile account|char",
    MODULES = "Модули:",
    ON = "вкл.",
    OFF = "выкл.",
    ERRORS_COUNT = "Записано ошибок: %d (уйдут в программу на ПК при /reload).",
    PROFILE_SET = "Профиль настроек: %s",
    PROFILE_ACCOUNT = "общий для аккаунта",
    PROFILE_CHAR = "свой у персонажа",

    GROUP_CORE = "Основа",
    GROUP_TRADE = "Торговля",
    GROUP_CRAFT = "Ремесло и услуги",
    GROUP_MONEY = "Деньги",
    GROUP_SERVICE = "Служебное",

    MODULE_Scan = "Скан и цены",
    MODULE_Tooltip = "Подсказка к предмету",
    MODULE_Deals = "Сделки",
    MODULE_Selling = "Продажи",
    MODULE_Mail = "Почта",
    MODULE_Ledger = "Учёт и капитал",
    MODULE_Disenchanter = "Распылитель",
    MODULE_Sync = "Связь с программой на ПК",
})
