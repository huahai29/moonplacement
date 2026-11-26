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


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_rows(path, key):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    by_ref = {row[key]: row for row in rows}
    assert len(by_ref) == len(rows), f"Repeated reference in {path}"
    return by_ref


def write_table(path, rows, *, shift_column=None, shift_ref=TARGET):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, list(next(iter(rows.values()))), lineterminator="\n")
        writer.writeheader()
        for ref, row in rows.items():
            if shift_column and ref == shift_ref:
                row = {**row, shift_column: str(Decimal(row[shift_column]) + OFFSET)}
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


def design_origin_offset():
    # Use KiCad design geometry, not Gerber or placement coordinates, as the oracle.
    fixture = json.loads((FIXTURE / "j1-design-pads.json").read_text(encoding="utf-8"), parse_float=Decimal)
    pi = Decimal("3.141592653589793238462643383279")
    x = y = area_sum = 0
    for group in fixture["groups"]:
        width, height = map(Decimal, group["size_mm"])
        if group["shape"] == "roundrect":
            radius = min(width, height) * group["radius_ratio"]
            area = width * height - (4 - pi) * radius**2
        else:
            assert group["shape"] == "oval"
            area = abs(width - height) * min(width, height) + pi * (min(width, height) / 2)**2
        for cx, cy in group["centers_mm"]:
            x += cx * area
            y -= cy * area  # PCB Y points down, while published copper Y points up.
            area_sum += area
    assert sum(len(group["centers_mm"]) for group in fixture["groups"]) == 20
    return float(x / area_sum), float(y / area_sum)


def pad_item(report, ref):
    return next(item["evidence"] for item in report["pad_evidence"] if item["ref"] == ref)


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

    largest = max((math.hypot(float(row["PosX"]) - float(easyeda[ref]["Ref X"]),
                              float(row["PosY"]) - float(easyeda[ref]["Ref Y"])), ref)
                  for ref, row in kicad.items())
    assert largest[1] == "R25" and close(largest[0], 0.000136)
    corrected = FIXTURE / "import-policy.json"
    corrected_policy = json.loads(corrected.read_text(encoding="utf-8"))
    configured = OUTPUT / "import-policy-without-pad-origin.json"
    original_policy = {key: value for key, value in corrected_policy.items() if key != "pad_origins"}
    save_json(configured, original_policy)
    assert set(original_policy["placement_import"]["expected_refs"]) == kicad.keys()
    matched = run("02-common-origins", CLI, [kicad_file, easyeda_file, configured], exit_code=0)
    assert matched["status"] == "pass" and matched["differences"] == []
    assert matched["frame"]["max_anchor_error_mm"] < 1e-9
    assert matched["baseline_count"] == matched["delivery_count"] == 97
    imported = matched["placement_import"]
    imported["delivery"]["excluded_refs"] = sorted(imported["delivery"]["excluded_refs"])
    assert imported == {
        "scope": "expected",
        "baseline": dict(x_column="PosX", y_column="PosY", footprint_prefix="", excluded_refs=[]),
        "delivery": dict(x_column="Ref X", y_column="Ref Y",
                         footprint_prefix="antmicro-footprints:", excluded_refs=extra),
    }

    partial = run("03-native-dual-copper", CLI, [kicad_file, easyeda_file, configured, TOP, BOTTOM], exit_code=1)
    assert partial["status"] == "different" and partial["pad_status"] == "incomplete"
    assert partial["pad_layers"][0]["status"] == "failed" and "FreePoly0" in partial["pad_layers"][0]["message"]
    assert partial["pad_layers"][1] == dict(side="bottom", status="complete", checked=44, targets=44)
    assert component_pairs(partial["pad_differences"]) == [("J1", "pad_offset")]
    changed_kicad = write_table(OUTPUT / "kicad-c17-shifted.csv", kicad, shift_column="PosX")
    changed_easyeda = write_table(OUTPUT / "easyeda-c17-shifted.csv", easyeda, shift_column="Ref X")
    deleted_easyeda = write_table(OUTPUT / "easyeda-c17-missing.csv", {k: v for k, v in easyeda.items() if k != TARGET})
    deleted_kicad = write_table(OUTPUT / "kicad-c17-missing.csv", {k: v for k, v in kicad.items() if k != TARGET})
    for label, baseline_csv, delivery_csv, kind in [
        ("07-missing-delivery", kicad_file, deleted_easyeda, "missing"),
        ("08-missing-both", deleted_kicad, deleted_easyeda, "missing_both"),
        ("09-missing-baseline", deleted_kicad, easyeda_file, "missing_baseline"),
    ]:
        missing = run(label, CLI, [baseline_csv, delivery_csv, configured], exit_code=1)
        assert component_pairs(missing["differences"]) == [(TARGET, kind)]
        assert sorted(missing["placement_import"]["delivery"]["excluded_refs"]) == extra
    shifted = run("10-c17-delivery-position", CLI, [kicad_file, changed_easyeda, configured], exit_code=1)
    assert component_pairs(shifted["differences"]) == [(TARGET, "position")]
    assert close(shifted["differences"][0]["distance_mm"], float(OFFSET))

    combined = run("11-dual-copper-both-shift", CLI,
                   [changed_kicad, changed_easyeda, configured, TOP, BOTTOM], exit_code=1)
    assert combined["pad_layers"] == partial["pad_layers"]
    assert combined["differences"] == []
    assert component_pairs(combined["pad_differences"]) == [(TARGET, "pad_offset"), ("J1", "pad_offset")]
    c17_shift = next(item for item in combined["pad_differences"] if item["ref"] == TARGET)
    assert close(c17_shift["distance_mm"], float(OFFSET))
    no_other_difference = run("12-dual-copper-corrected-origin", CLI,
                              [kicad_file, easyeda_file, corrected, TOP, BOTTOM], exit_code=2)
    assert no_other_difference["pad_layers"] == partial["pad_layers"]
    assert no_other_difference["differences"] == no_other_difference["pad_differences"] == []
    assert no_other_difference["reason"] == "incomplete_gerber_layers"

    cases = [
        ("04-native-bottom", kicad_file, easyeda_file, [], False),
        ("05-c17-delivery-shift", kicad_file, changed_easyeda, [(TARGET, "position")], True),
        ("06-c17-both-shift", changed_kicad, changed_easyeda, [], True),
    ]
    results = {}
    for name, baseline, delivery, table_differences, shifted in cases:
        result = run(name, BOTTOM_FIXTURE, [baseline, delivery, configured, BOTTOM], exit_code=0)
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

    dx, dy = design_origin_offset()
    correct_j1 = corrected_policy["pad_origins"][0]
    assert abs(correct_j1["dx_mm"] - dx) < 1e-12 and abs(correct_j1["dy_mm"] - dy) < 1e-12
    shifted_j1_kicad = write_table(OUTPUT / "kicad-j1-shifted.csv", kicad,
                                    shift_column="PosX", shift_ref="J1")
    shifted_j1_easyeda = write_table(OUTPUT / "easyeda-j1-shifted.csv", easyeda,
                                      shift_column="Ref X", shift_ref="J1")
    corrected_runs = {}
    for name, baseline, delivery, target in [
        ("13-corrected-normal-j1", kicad_file, easyeda_file, None),
        ("14-corrected-shifted-j1", shifted_j1_kicad, shifted_j1_easyeda, "J1"),
        ("15-corrected-shifted-c17", changed_kicad, changed_easyeda, TARGET),
    ]:
        report = run(name, BOTTOM_FIXTURE, [baseline, delivery, corrected, BOTTOM], exit_code=0)
        assert report["status"] == ("different" if target else "pass")
        assert report["differences"] == [] and report["pad_checked"] == 44
        assert component_pairs(report["pad_differences"]) == ([(target, "pad_offset")] if target else [])
        j1 = pad_item(report, "J1")
        assert j1["origin"]["status"] == "corrected" and j1["origin"]["matched_by"] == "ref"
        assert j1["pad_count"] == 20 and j1["within_tolerance"] == (target != "J1")
        assert close(j1["origin"]["raw_distance_mm"], math.hypot(-dx + (0.30 if target == "J1" else 0), dy))
        assert close(j1["distance_mm"], 0.30 if target == "J1" else 0.0)
        if target:
            assert close(report["pad_differences"][0]["distance_mm"], float(OFFSET))
        corrected_runs[name] = {"status": report["status"], "j1": j1,
                                "pad_differences": report["pad_differences"]}

    # An explicit review is incomplete, and never suppresses a confirmed difference elsewhere.
    manual_review = OUTPUT / "import-policy-review-j1.json"
    save_json(manual_review, {**original_policy, "pad_origins": [
        {"footprint": kicad["J1"]["Package"], "mode": "review", "source": "确认连接器原点来源"},
    ]})
    review = run("16-review-j1", BOTTOM_FIXTURE, [kicad_file, easyeda_file, manual_review, BOTTOM], exit_code=0)
    assert review["status"] == "indeterminate" and review["pad_checked"] == 43
    assert review["reason"] == "insufficient_pad_evidence" and review["pad_differences"] == []
    j1 = pad_item(review, "J1")
    assert j1["status"] == "unverified" and j1["reason"] == "pad_origin_review"
    assert j1["origin"]["status"] == "review" and j1["origin"]["matched_by"] == "footprint"
    assert close(j1["origin"]["raw_distance_mm"], math.hypot(dx, dy))
    review_shifted = run("17-review-j1-shifted-c17", BOTTOM_FIXTURE,
                         [changed_kicad, changed_easyeda, manual_review, BOTTOM], exit_code=0)
    assert review_shifted["status"] == "different"
    assert component_pairs(review_shifted["pad_differences"]) == [(TARGET, "pad_offset")]

    save_json(OUTPUT / "summary.json", dict(
        raw_table_counts={"kicad": len(kicad), "easyeda_pro": len(easyeda)},
        raw_difference_counts=counts, extra_designators=extra, midpoint_deltas_mm=position_deltas,
        common_origin_max_delta={"ref": largest[1], "distance_mm": largest[0]},
        rejected_top_macro="FreePoly0", bottom_cases=results,
        dual_layer_c17_offset_mm=c17_shift["distance_mm"],
        dual_layer_without_other_differences=no_other_difference["status"],
        j1_design_offset_mm={"x": dx, "y": dy}, corrected_bottom_cases=corrected_runs,
    ))
    print("KiCad / EasyEDA Pro: 97 shared references, 44 bottom targets, J1 corrected; J1 and C17 shifts detected")


if __name__ == "__main__":
    main()
