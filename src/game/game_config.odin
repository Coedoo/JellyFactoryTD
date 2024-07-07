package game

import "core:mem"

import dm "../dmcore"

LEVEL_MEMORY :: mem.Kilobyte * 512

PLAYER_SPEED :: 10

START_MONEY :: 1000
START_HP :: 200


// DEBUG
DEBUG_TILE_OVERLAY := false

// ENEMIES

Enemies := [?]Enemy {
    {
        name = "Test 1",
        speed = 8,
        maxHealth = 100,
        tint = dm.RED,
        moneyValue = 30,
        damage = 10,
    },

    {
        name = "Test 2",
        speed = 5,
        maxHealth = 200,
        tint = dm.GREEN,
        moneyValue = 70,
        damage = 25,
    },
}


// WAVES/LEVELS

Waves := [?]LevelWaves {
    {
        levelName = "Level_0",
        waves = {
            {
                {"Test 1", 20, 0.15},
                {"Test 2", 10, 0.7},
            },

            {
                {"Test 1", 30, 0.15},
            },
        },
    },

    {
        levelName = "Level_1",
        waves = {
            {
                {"Test 2", 30, 0.15},
            },
        },
    },
}
