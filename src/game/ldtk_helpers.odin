package game

import dm "../dmcore"
import "../ldtk"

FindTilesetDefinition :: proc(project: ldtk.Project, tilesetID: int) -> ^ldtk.Tileset_Definition {
    for &def in project.defs.tilesets {
        if def.uid == tilesetID {
            return &def
        }
    }

    return nil
}