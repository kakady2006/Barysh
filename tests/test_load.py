from conftest import ADDON_DIR, toc_files


def test_toc_lists_existing_files():
    for rel in toc_files():
        if rel == "Data/Market.lua":
            assert (ADDON_DIR / "Data/Market.default.lua").exists()
        else:
            assert (ADDON_DIR / rel).exists(), rel


def test_every_lua_file_is_in_toc():
    listed = set(toc_files()) | {"Data/Market.default.lua"}
    for path in ADDON_DIR.rglob("*.lua"):
        rel = path.relative_to(ADDON_DIR).as_posix()
        assert rel in listed, f"{rel} is not listed in Barysh.toc"


def test_loads_and_logs_in_without_errors(addon):
    addon.login()
    assert addon.errors() == []
    assert addon.g.BaryshDB.profile.deals.minProfit == 100
    assert any("Barysh" in line for line in addon.mock.printed.values())


def test_core_module_enabled_and_sync_off_by_default(addon):
    addon.login()
    assert addon.ns.modules.Scan.enabled
    assert addon.ns.modules.Deals.enabled
    assert not addon.ns.modules.Sync.enabled


def test_disabled_module_drops_events(addon):
    addon.login()
    deals = addon.ns.modules.Deals
    deals.RegisterEvent(deals, "AUCTION_HOUSE_SHOW", addon.lua.eval("function() end"))
    assert addon.ns.HasEventHandlers(deals)
    addon.ns.SetModuleEnabled("Deals", False)
    assert not deals.enabled
    assert not addon.ns.HasEventHandlers(deals)


def test_scan_cannot_be_disabled(addon):
    addon.login()
    addon.ns.SetModuleEnabled("Scan", False)
    assert addon.ns.modules.Scan.enabled


def test_character_profile_starts_as_copy(addon):
    addon.login()
    addon.ns.settings.deals.minProfit = 500
    addon.ns.SetProfileMode("char")
    assert addon.ns.settings.deals.minProfit == 500
    addon.ns.settings.deals.minProfit = 700
    addon.ns.SetProfileMode("account")
    assert addon.ns.settings.deals.minProfit == 500


def test_errors_are_recorded_and_deduplicated(addon):
    addon.login()
    boom = addon.lua.eval("function() error('boom') end")
    addon.ns.Safe(boom)
    addon.ns.Safe(boom)
    errors = list(addon.g.BaryshDB.errors.values())
    assert len(errors) == 1
    assert "boom" in errors[0].msg
    assert errors[0].count == 2


def test_error_before_saved_variables_is_kept(addon):
    addon.ns.Safe(addon.lua.eval("function() error('early') end"))
    addon.login()
    assert any("early" in msg for msg, _ in addon.errors())


def test_jobs_run_across_frames(addon):
    addon.login()
    addon.lua.execute("_G.steps = 0")
    step = addon.lua.eval("function() steps = steps + 1; WowMock.clock = WowMock.clock + 5; return steps >= 4 end")
    addon.ns.Jobs.Run("test", step)
    addon.mock.RunFrames(1)
    assert 0 < addon.g.steps < 4  # 8 ms budget per frame, 5 ms per step
    addon.mock.RunFrames(5)
    assert addon.g.steps == 4
    assert addon.ns.Jobs.Pending() == 0


def test_locale_falls_back_to_english(addon):
    addon.login()
    addon.ns.RegisterLocale("enUS", addon.table(ONLY_EN="english"))
    assert addon.ns.L.MODULE_Deals == "Сделки"
    assert addon.ns.L.ONLY_EN == "english"
    assert addon.ns.L.MISSING_KEY == "MISSING_KEY"


def test_slash_command_lists_modules(addon):
    addon.login()
    addon.g.SlashCmdList.BARYSH("modules")
    assert any("Сделки" in line for line in addon.mock.printed.values())
