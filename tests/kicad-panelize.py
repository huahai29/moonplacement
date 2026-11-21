"""Create a 2x2 test panel from an actual routed board using KiCad's editor API."""
import json
import re
import sys
from pathlib import Path

import pcbnew


def main():
    source, output, mapping = map(Path, sys.argv[1:])
    board = pcbnew.LoadBoard(str(source))
    footprints = list(board.GetFootprints())
    tracks = list(board.GetTracks())
    zones = list(board.Zones())
    drawings = list(board.GetDrawings())
    if not (footprints and tracks and zones and drawings):
        raise ValueError("Expected a routed board with zones and drawings")
    cells = []
    for row in (1, 2):
        for column in (1, 2):
            # KiCad editor Y is inverted in the output files.
            delta = pcbnew.VECTOR2I(pcbnew.FromMM(40 * (column - 1)),
                                   pcbnew.FromMM(-32 * (row - 1)))
            cell = (row - 1) * 2 + column - 1
            refs = {}
            for footprint in footprints:
                ref = footprint.GetReference()
                match = re.fullmatch(r"([A-Z]+)([1-9]\d*)", ref)
                if not match or int(match[2]) >= 1000:
                    raise ValueError(f"Unexpected reference: {ref}")
                name = ref if not cell else f"{match[1]}{1000 * cell + int(match[2])}"
                refs[ref] = name
                if cell:
                    duplicate = footprint.Duplicate()
                    duplicate.Move(delta)
                    duplicate.SetReference(name)
                    board.Add(duplicate)
            if cell:
                for item in (*tracks, *zones, *drawings):
                    duplicate = item.Duplicate()
                    duplicate.Move(delta)
                    board.Add(duplicate)
            cells.append({"row": row, "column": column, "refs": refs})
    if len(list(board.GetFootprints())) != 4 * len(footprints):
        raise ValueError("Not all footprints copied")
    if len(list(board.GetTracks())) != 4 * len(tracks) or len(list(board.Zones())) != 4 * len(zones):
        raise ValueError("Not all routing and zones copied")
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    pcbnew.SaveBoard(str(output), board)
    mapping.write_text(json.dumps(cells, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
