"""Compare CLI evidence with closed-form centroids using Python's Decimal."""

import json
import subprocess
from decimal import Decimal, getcontext
from pathlib import Path


getcontext().prec = 50
D = Decimal
PI = D("3.1415926535897932384626433832795028841971693993751")
LIMIT = D("0.25")
STEP = D("0.000001")
MAX_REFERENCE_ERROR = D("0.000000001")
OUT = Path("_build/pad-boundary")
CLI = "_build/js/debug/build/cmd/main/main.js"
CONVENTION = dict(unit="mm", bottom_x="direct", angle_sign=1,
                  top_angle_offset_deg=0, bottom_angle_offset_deg=0)
POLICY = dict(baseline=CONVENTION, delivery=CONVENTION, anchors=["A1", "A2", "A3"],
              rotation="0", anchor_tolerance_mm=0.02, position_tolerance_mm=0.05,
              angle_tolerance_deg=1, pad_tolerance_mm=float(LIMIT))


def mirror_rotate_scale(x, y):
    # Reflect X, turn 90 degrees counterclockwise, and double the result.
    return -2 * y, -2 * x


def flash(x, y):
    return f"X{int(D(x) * 1000000)}Y{int(D(y) * 1000000)}D03*"


def gerber(apertures, pad, *, panel):
    return (
        "%FSLAX46Y46*%%MOMM*%%TF.FileFunction,Copper,L1,Top*%%ADD10C,0.5*%"
        + apertures
        + ("%SRX2Y2I40J40*%" if panel else "")
        + f"D10*%TO.P,A1,1*%{flash(1, 1)}%TO.P,A2,1*%{flash(7, 1)}"
        + f"%TO.P,A3,1*%{flash(1, 7)}%TO.P,D1,1*%{pad}%TD*%"
        + ("%SR*%" if panel else "")
        + "M02*\n"
    )


def cases():
    # Two rectangular flashes with areas 1 and 3 mm².
    yield ("weighted-rectangles", (D("5.5"), D(4)),
           gerber("%ADD11R,1X1*%%ADD12R,3X1*%", f"D11*{flash(4, 4)}D12*{flash(6, 4)}",
                  panel=False), False, 2)

    flash_x, flash_y = D(8), D(9)
    dx, dy = mirror_rotate_scale(D("0.5"), D(1))
    transform = "D11*%LMX*%%LR90*%%LS2*%"
    yield ("mirrored-rotated-circle", (flash_x + dx, flash_y + dy),
           gerber("%AMOffset*1,1,0.5,0.5,1,0*%%ADD11Offset*%",
                  transform + flash(flash_x, flash_y), panel=False), False, 1)

    # Subtract the first moments of two circular holes from a centred rectangle.
    holes = [(D("0.4"), D("-1")), (D("0.6"), D("0.8"))]
    remaining_area = D(15) - sum(PI * r * r for r, _ in holes)
    centre_x = -sum(PI * r * r * x for r, x in holes) / remaining_area
    dx, dy = mirror_rotate_scale(centre_x, D(0))
    aperture = "%AMWindow*21,1,5,3,0,0,0*1,0,0.8,-1,0*1,0,1.2,0.8,0*%%ADD11Window*%"
    for name, panel in [("asymmetric-holes", False), ("holes-selected-cell", True)]:
        yield (name, (flash_x + dx, flash_y + dy),
               gerber(aperture, transform + flash(flash_x, flash_y), panel=panel), panel, 1)


def audit(layer, csv, *, panel):
    args = ["node", CLI, str(csv), str(csv), str(OUT / "policy.json"), str(layer)]
    if panel:
        args += ["--panel-cell", "2,2"]
    run = subprocess.run(args, capture_output=True, encoding="utf-8", check=False)
    return run.returncode, json.loads(run.stdout)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "policy.json").write_text(json.dumps(POLICY), encoding="utf-8")
    results = []
    for name, centre, layer_text, panel, pads in cases():
        layer = OUT / f"{name}.gbr"
        layer.write_text(layer_text, encoding="utf-8")
        for label, requested in [
            ("below", LIMIT - STEP),
            ("equal", LIMIT),
            ("above", LIMIT + STEP),
        ]:
            x = centre[0] + requested
            y = centre[1].quantize(D("1e-12"))
            dx, dy = x - centre[0], y - centre[1]
            if label == "equal" and dy:
                # An irrational hole centroid cannot be written exactly in CSV.
                continue
            reference = (dx * dx + dy * dy).sqrt()
            within = reference <= LIMIT
            status = "pass" if within else "different"
            csv = OUT / f"{name}-{label}.csv"
            csv.write_text("Ref,PosX,PosY,Rot,Side\nA1,1,1,0,top\nA2,7,1,0,top\n"
                           f"A3,1,7,0,top\nD1,{x:f},{y:f},0,top\n", encoding="utf-8")
            code, report = audit(layer, csv, panel=panel)
            assert (code, report["status"]) == (int(status == "different"), status), (
                name, label, code, report["status"], report.get("pad_differences"), report.get("reason"),
            )
            assert report["pad_status"] == "complete" and not report["differences"], (name, label)
            cells = report["panel_cells"]
            if panel:
                assert len(cells) == 1 and (cells[0]["row"], cells[0]["column"]) == (2, 2)
                assert (cells[0]["offset_x_mm"], cells[0]["offset_y_mm"]) == (40, 40)
            else:
                assert not cells
            actual = next(item["evidence"] for item in report["pad_evidence"] if item["ref"] == "D1")
            assert actual["status"] == "by_reference" and actual["pad_count"] == pads
            assert actual["within_tolerance"] == within, (name, label, actual)
            error = abs(D(str(actual["distance_mm"])) - reference)
            assert error <= MAX_REFERENCE_ERROR, (name, label, error)
            diffs = report["pad_differences"]
            if not within:
                assert [(item["ref"], item["kind"]) for item in diffs] == [("D1", "pad_offset")]
                assert abs(D(str(diffs[0]["delta_x_mm"])) - dx) <= MAX_REFERENCE_ERROR
                assert abs(D(str(diffs[0]["delta_y_mm"])) - dy) <= MAX_REFERENCE_ERROR
            else:
                assert not diffs
            results.append(dict(case=name, boundary=label, status=status,
                                reference_centroid_mm=[str(c) for c in centre],
                                reference_distance_mm=str(reference),
                                reported_distance_mm=actual["distance_mm"], error_mm=str(error)))
    assert len(results) == 10
    result = {"tolerance_mm": str(LIMIT), "step_mm": str(STEP),
              "max_error_mm": str(max(D(row["error_mm"]) for row in results)), "cases": results}
    (OUT / "results.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{len(results)} centroid oracle cases passed (maximum error {result['max_error_mm']} mm)")


if __name__ == "__main__":
    main()
