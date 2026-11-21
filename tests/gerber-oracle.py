"""Compare actual copper points with PyGerber; only used for validation."""
import csv
import json
import math
import subprocess
import sys
from importlib.metadata import version
from pathlib import Path

from PIL import Image
from pygerber.gerberx3.api.v2 import GerberFile

OUT = Path("_build/gerber-comparison")
CLI = "_build/js/debug/build/cmd/main/main.js"
DPMM = 80
PANEL = Path("examples/gerber")
CONVENTION = {"unit": "mm", "bottom_x": "direct", "angle_sign": 1,
              "top_angle_offset_deg": 0, "bottom_angle_offset_deg": 0}
POLICY = {
    "baseline": CONVENTION,
    "delivery": CONVENTION,
    "anchors": ["A1", "A2", "A3"],
    "rotation": "0",
    "position_tolerance_mm": 0.05,
    "angle_tolerance_deg": 1,
    "anchor_tolerance_mm": 0.02,
    "pad_tolerance_mm": 0.000001,
}


def moonplacement(layer, name, points):
    source = OUT / (name + ".csv")
    with source.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(("Ref", "Val", "Package", "PosX", "PosY", "Rot", "Side"))
        for n, (x, y) in enumerate(((0, 0), (1, 0), (0, 1)), 1):
            writer.writerow((f"A{n}", "probe", "probe", x, y, 0, "top"))
        for n, (x, y, _) in enumerate(points, 1):
            writer.writerow((f"PROBE{n}", "probe", "probe", x, y, 0, "top"))
    config = OUT / "policy.json"
    config.write_text(json.dumps(POLICY), encoding="utf-8")
    result = subprocess.run(
        ["node", CLI, str(source), str(source), str(config), str(layer)],
        capture_output=True, encoding="utf-8", check=False,
    )
    assert result.returncode == 2, (layer, result.stdout, result.stderr)
    report = json.loads(result.stdout)
    assert report["reason"] == "insufficient_pad_evidence", report
    probes = {row["ref"]: row["evidence"]["status"] for row in report["pad_evidence"]}
    return [probes[f"PROBE{n}"] for n in range(1, len(points) + 1)]


def compare(layer, name, points):
    parsed = GerberFile.from_file(layer).parse()
    bounds = parsed.get_info()
    png = OUT / (name + ".png")
    parsed.render_raster(png, dpmm=DPMM)
    with Image.open(png) as image:
        pixels = image.convert("RGB")
    from_moon = moonplacement(layer, name, points)
    report = []
    for (x, y, expected), status in zip(points, from_moon, strict=True):
        u = math.floor((x - float(bounds.min_x_mm)) * DPMM)
        v = pixels.height - 1 - math.floor((y - float(bounds.min_y_mm)) * DPMM)
        assert 1 <= u < pixels.width - 1 and 1 <= v < pixels.height - 1, (layer, x, y)
        window = {
            pixels.getpixel((u + du, v + dv)) != (0, 0, 0)
            for du in (-1, 0, 1) for dv in (-1, 0, 1)
        }
        assert window == {expected}, (layer, x, y, expected, window)
        assert status == ("copper_only" if expected else "unverified"), (layer, x, y, status)
        report.append({"x_mm": x, "y_mm": y, "copper": expected, "moonplacement": status})
    print(f"{name}: {len(report)} matching probes")
    return report


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    panel = [(10, 10, True), (20, 20, True), (24, 13, True),
             (34, 13, True), (29, 13, False), (24, 14.2, False)]
    report = {"renderer": f"PyGerber {version('pygerber')}", "pixels_per_mm": DPMM,
              "maximum_pixel_neighborhood_mm": 2 / DPMM, "files": {}}
    for name in ("panel-ab-sr", "panel-ab-expanded"):
        report["files"][name] = compare(PANEL / (name + ".gbr"), name, panel)
    if len(sys.argv) > 1:
        top = next(path for path in Path(sys.argv[1]).glob("*.gbr")
                   if "%TF.FileFunction,Copper,L1,Top" in path.read_text(encoding="utf-8"))
        real = [(10, -10, True), (20, -20, True), (22, -13, True),
                (22, -14, False), (20, -18, False)]
        report["files"]["kicad-top"] = compare(top, "kicad-top", real)
        version_path = Path(sys.argv[1]).parent / "kicad-version.txt"
        report["kicad"] = version_path.read_text(encoding="utf-8").strip()
    (OUT / "comparison.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
