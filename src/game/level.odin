package game

import dm "../dmcore"
import "core:math"
import "core:math/rand"
import "core:math/linalg/glsl"
import "core:fmt"
import "core:slice"

import "../ldtk"

Tile :: struct {
    worldPos: v2,
    sprite: dm.Sprite,
}

LoadGrid :: proc() {
    tilesHandle := dm.GetTextureAsset("tiles.png")
    // levelAsset := LevelAsset

    level := dm.GetAssetData("level1.ldtk")
    project, ok := ldtk.load_from_memory(level.fileData).?

    if ok == false {
        fmt.eprintln("Failed to load level file")
        return
    }

    for level in project.levels {
        levelPxSize := iv2{i32(level.px_width), i32(level.px_height)}
        levelSize := dm.ToV2(levelPxSize) / 32
        centerOffset := levelSize / 2 - {0.5, 0.5}

        gameState.gridX = int(levelSize.x)
        gameState.gridY = int(levelSize.y)

        for layer in level.layer_instances {
            yOffset := layer.c_height * layer.grid_size

            if layer.identifier == "Base" {
                tiles := layer.type == .Tiles ? layer.grid_tiles : layer.auto_layer_tiles
                gameState.grid = make([]Tile, len(tiles))

                for tile, i in tiles {
                    posX := f32(tile.px.x) / f32(layer.grid_size)
                    posY := f32(-tile.px.y + yOffset) / f32(layer.grid_size)

                    sprite := dm.CreateSprite(tilesHandle, 
                        dm.RectInt{i32(tile.src.x), i32(tile.src.y), 32, 32})
                    gameState.grid[i] = Tile {
                        sprite = sprite,
                        worldPos = v2{posX, posY} - centerOffset
                    }
                }
            }
        }
    }

}