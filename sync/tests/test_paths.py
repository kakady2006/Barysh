from barysh_sync.paths import find_game_dirs, market_file, saved_variables_files


def make_install(root, flavor, account="ACCOUNT1", addon=True):
    game = root / flavor
    if addon:
        (game / "Interface" / "AddOns" / "Barysh").mkdir(parents=True)
    sv = game / "WTF" / "Account" / account / "SavedVariables"
    sv.mkdir(parents=True)
    (sv / "Barysh.lua").write_text("BaryshDB = {}\n", encoding="utf-8")
    return game


def test_finds_only_flavors_with_barysh(tmp_path):
    forever = make_install(tmp_path, "_forever_")
    make_install(tmp_path, "_retail_", addon=False)
    assert find_game_dirs([tmp_path, tmp_path / "missing"]) == [forever]


def test_saved_variables_per_account(tmp_path):
    game = make_install(tmp_path, "_forever_", account="A")
    make_install(tmp_path, "_forever_", account="B", addon=False)
    names = [p.parts[-3] for p in saved_variables_files(game)]
    assert names == ["A", "B"]


def test_market_file_inside_addon(tmp_path):
    assert market_file(tmp_path).as_posix().endswith("Interface/AddOns/Barysh/Data/Market.lua")
