local _, ns = ...

-- VERIFY: disenchant table taken from Classic 1.12 (by item level). Check outcomes in game.
-- Materials by item ID.
local M = {
    STRANGE_DUST = 10940, SOUL_DUST = 11083, VISION_DUST = 11137, DREAM_DUST = 11176, ILLUSION_DUST = 16204,
    LESSER_MAGIC = 10938, GREATER_MAGIC = 10939,
    LESSER_ASTRAL = 10998, GREATER_ASTRAL = 11082,
    LESSER_MYSTIC = 11134, GREATER_MYSTIC = 11135,
    LESSER_NETHER = 11174, GREATER_NETHER = 11175,
    LESSER_ETERNAL = 16202, GREATER_ETERNAL = 16203,
    SMALL_GLIMMERING = 10978, LARGE_GLIMMERING = 11084,
    SMALL_GLOWING = 11138, LARGE_GLOWING = 11139,
    SMALL_RADIANT = 11177, LARGE_RADIANT = 11178,
    SMALL_BRILLIANT = 14343, LARGE_BRILLIANT = 14344,
    NEXUS_CRYSTAL = 20725,
}

ns.DisenchantData = {
    materials = M,
    -- Uncommon (green): by max item level. dust / essence / shard = { itemID, min, max }.
    -- Armor: 75% dust, 20% essence, 5% shard; weapons swap dust and essence chances.
    uncommon = {
        { maxIlvl = 15, first = true, dust = { M.STRANGE_DUST, 1, 2 }, essence = { M.LESSER_MAGIC, 1, 2 } },
        { maxIlvl = 20, dust = { M.STRANGE_DUST, 2, 3 }, essence = { M.GREATER_MAGIC, 1, 2 }, shard = { M.SMALL_GLIMMERING, 1, 1 } },
        { maxIlvl = 25, dust = { M.STRANGE_DUST, 4, 6 }, essence = { M.LESSER_ASTRAL, 1, 2 }, shard = { M.SMALL_GLIMMERING, 1, 1 } },
        { maxIlvl = 30, dust = { M.SOUL_DUST, 1, 2 }, essence = { M.GREATER_ASTRAL, 1, 2 }, shard = { M.LARGE_GLIMMERING, 1, 1 } },
        { maxIlvl = 35, dust = { M.SOUL_DUST, 2, 5 }, essence = { M.LESSER_MYSTIC, 1, 2 }, shard = { M.SMALL_GLOWING, 1, 1 } },
        { maxIlvl = 40, dust = { M.VISION_DUST, 1, 2 }, essence = { M.GREATER_MYSTIC, 1, 2 }, shard = { M.LARGE_GLOWING, 1, 1 } },
        { maxIlvl = 45, dust = { M.VISION_DUST, 2, 5 }, essence = { M.LESSER_NETHER, 1, 2 }, shard = { M.SMALL_RADIANT, 1, 1 } },
        { maxIlvl = 50, dust = { M.DREAM_DUST, 1, 2 }, essence = { M.GREATER_NETHER, 1, 2 }, shard = { M.LARGE_RADIANT, 1, 1 } },
        { maxIlvl = 55, dust = { M.DREAM_DUST, 2, 5 }, essence = { M.LESSER_ETERNAL, 1, 2 }, shard = { M.SMALL_BRILLIANT, 1, 1 } },
        { maxIlvl = 60, dust = { M.ILLUSION_DUST, 1, 2 }, essence = { M.GREATER_ETERNAL, 1, 2 }, shard = { M.LARGE_BRILLIANT, 1, 1 } },
        { maxIlvl = 65, dust = { M.ILLUSION_DUST, 2, 5 }, essence = { M.GREATER_ETERNAL, 2, 3 }, shard = { M.LARGE_BRILLIANT, 1, 1 } },
    },
    -- Rare (blue): always a shard. Top tier has a small chance of a Nexus Crystal.
    rare = {
        { maxIlvl = 25, outcomes = { { 1, M.SMALL_GLIMMERING, 1, 1 } } },
        { maxIlvl = 30, outcomes = { { 1, M.LARGE_GLIMMERING, 1, 1 } } },
        { maxIlvl = 35, outcomes = { { 1, M.SMALL_GLOWING, 1, 1 } } },
        { maxIlvl = 40, outcomes = { { 1, M.LARGE_GLOWING, 1, 1 } } },
        { maxIlvl = 45, outcomes = { { 1, M.SMALL_RADIANT, 1, 1 } } },
        { maxIlvl = 50, outcomes = { { 1, M.LARGE_RADIANT, 1, 1 } } },
        { maxIlvl = 55, outcomes = { { 1, M.SMALL_BRILLIANT, 1, 1 } } },
        { maxIlvl = 65, outcomes = { { 0.995, M.LARGE_BRILLIANT, 1, 1 }, { 0.005, M.NEXUS_CRYSTAL, 1, 1 } } },
    },
    -- Epic (purple).
    epic = {
        { minIlvl = 40, maxIlvl = 45, outcomes = { { 1, M.SMALL_RADIANT, 2, 4 } } },
        { maxIlvl = 50, outcomes = { { 1, M.LARGE_RADIANT, 2, 4 } } },
        { maxIlvl = 55, outcomes = { { 1, M.SMALL_BRILLIANT, 2, 4 } } },
        { maxIlvl = 60, outcomes = { { 1, M.NEXUS_CRYSTAL, 1, 1 } } },
        { maxIlvl = 80, outcomes = { { 1, M.NEXUS_CRYSTAL, 1, 2 } } },
    },
}
