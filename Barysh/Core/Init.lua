local ADDON, ns = ...

ns.name = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

-- Values not yet confirmed on the Forever client. Each one is checked in docs/ingame-checklist.md.
ns.const = {
    -- VERIFY: auction cut on Forever (Classic values assumed).
    cutFaction = 0.05,
    cutNeutral = 0.15,
    -- VERIFY: full scan throttle (retail: 15 minutes per account).
    replicateCooldown = 15 * 60,
}
