package game


Tileset := TileSet {
    atlas = {
        texAssetPath = "kenney_tilemap.png",
        cellSize = {16, 16},
        spacing = {1, 1},
        padding = {0, 0},
    },

    tiles = {
        // name, category, atlasPos, flags, energy

        {"base",     .BuildSpace, {0, 0}, {}, .None },
        {"rocks 1 ", .BuildSpace, {0, 1}, {}, .None },
        {"rocks 2",  .BuildSpace, {0, 2}, {}, .None },

        {"road",  .Road, {0, 4}, { .Walkable }, .None },

        {"Red Crystals",   .Resources, {0, 3}, {}, .Red },
        {"Green Crystals", .Resources, {1, 3}, {}, .Green },
        {"Blue Crystals",  .Resources, {2, 3}, {}, .Blue },
        {"Cyan Crystals",  .Resources, {3, 3}, {}, .Cyan },
    },
}