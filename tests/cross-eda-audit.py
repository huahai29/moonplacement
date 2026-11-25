"""Replay the pinned KiCad and EasyEDA Pro native exports."""

import csv
import hashlib
import json
import math
import subprocess
from collections import Counter
from decimal import Decimal
from pathlib import Path


FIXTURE = Path("examples/hardware/antmicro-usb-c-power-adapter")
OUTPUT = Path("_build/cross-eda/validation")
BUILD = Path("_build/js/debug/build")
CLI = BUILD / "cmd/main/main.js"
BOTTOM_FIXTURE = BUILD / "tests/cross-eda/cross-eda.js"
TOP = FIXTURE / "usb-c-power-adapter-F_Cu.gbr"
BOTTOM = FIXTURE / "usb-c-power-adapter-B_Cu.gbr"
ANCHORS = ["C1", "C10", "C15"]
TARGET = "C17"
OFFSET = Decimal("0.30")
KICAD_FIELDS = ["Ref", "Val", "Package", "PosX", "PosY", "Rot", "Side"]


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_rows(path, key):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    by_ref = {row[key]: row for row in rows}
    assert len(by_ref) == len(rows), f"Repeated reference in {path}"
    return by_ref


def write_table(path, rows, *, shift=False):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, KICAD_FIELDS, lineterminator="\n")
        writer.writeheader()
        for row in rows.values():
            if shift and row["Ref"] == TARGET:
                row = {**row, "PosX": str(Decimal(row["PosX"]) + OFFSET)}
            writer.writerow(row)
    return path


def run(name, executable, args, *, exit_code):
    proc = subprocess.run(["node", str(executable), *map(str, args)],
                          capture_output=True, encoding="utf-8", check=False)
    assert proc.returncode == exit_code, (name, proc.stderr or proc.stdout)
    result = json.loads(proc.stdout)
    save_json(OUTPUT / (name + ".json"), result)
    return result


def component_pairs(items):
    return sorted((item["ref"], item["kind"]) for item in items)


def close(actual, expected):
    return math.isclose(actual, expected, abs_tol=1e-9, rel_tol=0)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for entry in (FIXTURE / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        expected, name = entry.split(maxsplit=1)
        assert hashlib.sha256((FIXTURE / name).read_bytes()).hexdigest() == expected, name
    kicad_file = FIXTURE / "kicad-placement.csv"
    easyeda_file = FIXTURE / "easyeda-pro-placement.csv"
    kicad = read_rows(kicad_file, "Ref")
    easyeda = read_rows(easyeda_file, "Designator")
    extra = sorted(easyeda.keys() - kicad.keys())
    assert len(kicad) == 97 and len(easyeda) == 124 and len(extra) == 27
    assert kicad.keys() <= easyeda.keys()
    assert Counter(row["Side"] for row in kicad.values()) == {"top": 53, "bottom": 44}
    assert kicad[TARGET]["Side"] == "bottom" and TARGET not in ANCHORS

    convention = dict(unit="mm", bottom_x="direct", angle_sign=1,
                      top_angle_offset_deg=0, bottom_angle_offset_deg=0)
    policy = OUTPUT / "policy.json"
    save_json(policy, dict(baseline=convention, delivery=convention, anchors=ANCHORS,
                           rotation="0", anchor_tolerance_mm=0.02, position_tolerance_mm=0.05,
                           angle_tolerance_deg=1, pad_tolerance_mm=0.1))

    raw = run("01-native-tables", CLI, [kicad_file, easyeda_file, policy], exit_code=1)
    counts = Counter(item["kind"] for item in raw["differences"])
    assert raw["status"] == "different" and counts == {"extra": 27, "package": 97, "position": 4}
    position_deltas = {item["ref"]: item["distance_mm"] for item in raw["differences"]
                       if item["kind"] == "position"}
    assert position_deltas.keys() == {"J1", "Q1", "J2", "J3"}
    assert close(position_deltas["J1"], 1.123)

    # Select the same assembly scope and compare the footprint origins.
    # Strip only the known library prefix from this pinned export.
    prefix = "antmicro-footprints:"
    assert all(easyeda[ref]["Footprint"].startswith(prefix) for ref in kicad)
    common = {ref: dict(Ref=ref, Val=easyeda[ref]["Comment"],
                        Package=easyeda[ref]["Footprint"].removeprefix(prefix),
                        PosX=easyeda[ref]["Ref X"], PosY=easyeda[ref]["Ref Y"],
                        Rot=easyeda[ref]["Rotation"], Side=easyeda[ref]["Layer"])
              for ref in kicad}
    largest = max((math.hypot(float(row["PosX"]) - float(common[ref]["PosX"]),
                              float(row["PosY"]) - float(common[ref]["PosY"])), ref)
                  for ref, row in kicad.items())
    assert largest[1] == "R25" and close(largest[0], 0.000136)
    comparable = write_table(OUTPUT / "easyeda-common-origins.csv", common)
    matched = run("02-common-origins", CLI, [kicad_file, comparable, policy], exit_code=0)
    assert matched["status"] == "pass" and matched["differences"] == []
    assert matched["frame"]["max_anchor_error_mm"] < 1e-9

    blocked = run("03-native-dual-copper", CLI, [kicad_file, comparable, policy, TOP, BOTTOM], exit_code=64)
    assert blocked["status"] == "input_error" and "FreePoly0" in blocked["message"]
    assert Path(blocked["field"]) == TOP
    changed_kicad = write_table(OUTPUT / "kicad-c17-shifted.csv", kicad, shift=True)
    changed_easyeda = write_table(OUTPUT / "easyeda-c17-shifted.csv", common, shift=True)
    cases = [
        ("04-native-bottom", kicad_file, comparable, [], False),
        ("05-c17-delivery-shift", kicad_file, changed_easyeda, [(TARGET, "position")], True),
        ("06-c17-both-shift", changed_kicad, changed_easyeda, [], True),
    ]
    results = {}
    for name, baseline, delivery, table_differences, shifted in cases:
        result = run(name, BOTTOM_FIXTURE, [baseline, delivery, policy, BOTTOM], exit_code=0)
        assert result["status"] == "different"  # J1 is present in every raw-bottom report.
        assert result["pad_status"] == "complete" and result["pad_checked"] == 44
        assert result["pad_sides"] == ["bottom"]
        assert component_pairs(result["differences"]) == table_differences
        expected_pads = [(TARGET, "pad_offset"), ("J1", "pad_offset")] if shifted else [("J1", "pad_offset")]
        assert component_pairs(result["pad_differences"]) == expected_pads
        connector = next(item for item in result["pad_differences"] if item["ref"] == "J1")
        assert close(connector["distance_mm"], 2.26630145600751)
        c17 = next(item["evidence"] for item in result["pad_evidence"] if item["ref"] == TARGET)
        assert c17["status"] == "by_reference" and c17["pad_count"] == 2
        assert c17["within_tolerance"] != shifted
        assert close(c17["distance_mm"], float(OFFSET) if shifted else 0.0)
        results[name] = dict(table_differences=len(table_differences), c17_distance_mm=c17["distance_mm"],
                             bottom_checked=result["pad_checked"], j1_distance_mm=connector["distance_mm"])

    save_json(OUTPUT / "summary.json", dict(
        raw_table_counts={"kicad": len(kicad), "easyeda_pro": len(easyeda)},
        raw_difference_counts=counts, extra_designators=extra, midpoint_deltas_mm=position_deltas,
        common_origin_max_delta={"ref": largest[1], "distance_mm": largest[0]},
        rejected_top_macro="FreePoly0", bottom_cases=results,
    ))
    print("KiCad / EasyEDA Pro: 97 shared references, raw differences preserved, 44 bottom pads checked")


if __name__ == "__main__":
    main()
