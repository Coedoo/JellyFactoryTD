package game

import "core:mem"

import dm "../dmcore"

LEVEL_MEMORY :: mem.Kilobyte * 512

PLAYER_SPEED :: 10
BUILDING_DISTANCE :: 5

START_MONEY :: 1000
START_HP :: 200



START_LEVEL :: "Level_0"

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

// BUILDINGS

Buildings := [?]Building {
    {
        name = "Factory 1",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .ProduceEnergy, .SendsEnergy },

        restrictedTiles = { .Walls },

        cost = 100,

        producedEnergyType = .Blue, 
        energyStorage = 100,
        energyProduction = 25,
        balanceType = .Full,

        packetSize = 10,
        packetSpawnInterval = 0.2,
    },
    
    {
        name = "Factory 2",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .ProduceEnergy, .SendsEnergy },

        restrictedTiles = { .Walls },

        cost = 100,

        producedEnergyType = .Green,
        energyStorage = 100,
        energyProduction = 25,
        balanceType = .Full,

        packetSize = 10,
        packetSpawnInterval = 0.2,
    },

    {
        name = "Factory 3",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .ProduceEnergy, .SendsEnergy },

        restrictedTiles = { .Walls },

        cost = 100,

        producedEnergyType = .Red,
        energyStorage = 100,
        energyProduction = 25,
        balanceType = .Full,

        packetSize = 10,
        packetSpawnInterval = 0.2,
    },

    {
        name = "Turret 1",
        spriteName = "turret_test_4.png",
        spriteRect = {0, 0, 32, 32},
        turretSpriteRect = {0, 32, 32, 32},
        turretSpriteOrigin = {0.5, 0.5},

        size = {2, 2},

        flags = {.Attack, .RequireEnergy, .RotatingTurret},

        cost = 200,

        energyStorage = 100,
        // energyProduction = 25,
        balanceType = .Full,

        attackType = .Simple,
        range = 4,
        energyRequired = 8,
        reloadTime = 0.2,
        damage = 10,
    },

    {
        name = "Battery",
        spriteName = "buildings.png",
        spriteRect = {32, 0, 32, 32},

        size = {1, 1},

        flags = { .RequireEnergy, .SendsEnergy },

        restrictedTiles = {},

        cost = 100,

        energyStorage = 500,
        balanceType = .Balanced,

        packetSize = 10,
        packetSpawnInterval = 0.2,
    },


    {
        name = "Cannon 1",
        spriteName = "turret_test_4.png",
        spriteRect = {32, 0, 32, 32},
        turretSpriteRect = {32, 32, 32, 32},
        turretSpriteOrigin = {0.5, 0.5},

        size = {2, 2},

        flags = {.Attack, .RequireEnergy, .RotatingTurret},

        cost = 200,

        energyStorage = 100,
        // energyProduction = 25,
        balanceType = .Full,

        attackType = .Cannon,

        range = 4,
        energyRequired = 10,
        reloadTime = 0.2,
        damage = 20,
        attackRadius = 3,
    },

    {
        name = "Modifier Speed",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .EnergyModifier },

        cost = 100,

        energyModifier = SpeedUpModifier {
            costPercent = 0.2,
            multiplier = 3,
        }
    },

    {
        name = "Modifier Color",
        spriteName = "buildings.png",
        spriteRect = {0, 0, 32, 32},

        size = {1, 1},

        flags = { .EnergyModifier },

        cost = 100,

        energyModifier = ChangeColorModifier {
            costPercent = 0.4,
            targetType = .Cyan
        }
    },
}