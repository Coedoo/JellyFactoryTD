package game

import "core:mem"

import dm "../dmcore"

LEVEL_MEMORY :: mem.Kilobyte * 512
PATH_MEMORY :: mem.Kilobyte * 128

PLAYER_SPEED :: 10
BUILDING_DISTANCE :: 5

START_MONEY :: 1000
START_HP :: 200


SHOT_VISUAL_TIMER :: 0.1


START_LEVEL :: "Level_0"

STARTING_STAGE :: GameStage.Gameplay

// ENEMIES

Enemies := [EnemyType]Enemy {
    .Regular = {
        name = "Regular",
        speed = 8,
        maxHealth = 100,
        tint = dm.RED,
        moneyValue = 30,
        damage = 10,
    },

    .Fast = {
        name = "Fast",
        speed = 12,
        maxHealth = 50,
        tint = dm.CYAN,
        moneyValue = 30,
        damage = 10,
    },


    .Big = {
        name = "Big",
        speed = 5,
        maxHealth = 200,
        tint = dm.GREEN,
        moneyValue = 70,
        damage = 25,
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

        // restrictedTiles = EnergyTileTypes,

        cost = 100,

        // producedEnergyType = .Blue, 
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
        damage = 30,
    },

    {
        name = "Battery",
        spriteName = "buildings.png",
        spriteRect = {32, 0, 32, 32},

        size = {1, 1},

        flags = { .RequireEnergy, .SendsEnergy },

        // restrictedTiles = {},

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

    {
        name = "Wall",
        spriteName = "kenney_tilemap.png",
        spriteRect = {4 * 16 + 3, 3 * 16 + 2, 16, 16},

        size = {1, 1},

        flags = {},

        cost = 50,
    },
}