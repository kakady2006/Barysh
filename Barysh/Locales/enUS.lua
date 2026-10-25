local _, ns = ...

ns.RegisterLocale("enUS", {
    LOADED = "Barysh %s loaded. Type /barysh for commands.",
    HELP = "Commands: /barysh modules, /barysh errors, /barysh profile account|char",
    MODULES = "Modules:",
    ON = "on",
    OFF = "off",
    ERRORS_COUNT = "Recorded errors: %d (sent to the PC app on /reload).",
    PROFILE_SET = "Settings profile: %s",
    PROFILE_ACCOUNT = "shared for account",
    PROFILE_CHAR = "this character",

    GROUP_CORE = "Core",
    GROUP_TRADE = "Trading",
    GROUP_CRAFT = "Crafting and services",
    GROUP_MONEY = "Money",
    GROUP_SERVICE = "Utility",

    MODULE_Scan = "Scan and prices",
    MODULE_Tooltip = "Item tooltip",
    MODULE_Deals = "Deals",
    MODULE_Selling = "Selling",
    MODULE_Mail = "Mail",
    MODULE_Ledger = "Ledger and capital",
    MODULE_Disenchanter = "Disenchanter",
    MODULE_Sync = "PC app link",
})
