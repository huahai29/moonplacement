"""Numerical cross-check for the MoonBit Release registration and CLI."""

import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np


RELEASE = Path("_build/js/release/build")
EPS_MM = 1e-9
THRESHOLD_MM = 0.04
SOURCE = np.array([(1, 2), (8, -5), (-3, 9), (17, 12), (-12, -7),
                   (2, 21), (-15, 16), (19, -15)], dtype=float)


def node(package, args=(), *, inputs=None, exit_code=0):
    entry = RELEASE / package / (Path(package).name + ".js")
    result = subprocess.run(
        ["node", str(entry), *map(str, args)],
        input=inputs, encoding="utf-8", capture_output=True, check=False,
    )
    assert result.returncode == exit_code, result.stderr or result.stdout
    return json.loads(result.stdout)


def reference_fit(model, source, target):
    if model == "affine":
        design = np.column_stack((source, np.ones(len(source))))
        coefficients, _, rank, _ = np.linalg.lstsq(design, target, rcond=None)
        assert rank == 3
        return coefficients[:2], coefficients[2]
    p, q = source - source.mean(axis=0), target - target.mean(axis=0)
    left, singular_values, right = np.linalg.svd(p.T @ q)
    handedness = np.array([1.0, np.linalg.det(left @ right)])
    matrix = left @ np.diag(handedness) @ right
    if model == "similarity":
        matrix *= (singular_values @ handedness) / np.sum(p ** 2)
    return matrix, target.mean(axis=0) - source.mean(axis=0) @ matrix


def registration_cases():
    rng = np.random.default_rng(18439)
    for model in ("rigid", "similarity", "affine"):
        for degrees in (-137, 31, 173):
            radians = np.deg2rad(degrees)
            c, s = np.cos(radians), np.sin(radians)
            matrix = np.array([[c, s], [-s, c]])
            if model == "similarity":
                matrix *= 1.27
            elif model == "affine":
                matrix = np.array([[1.12, 0.19], [-0.23, 0.84]]) @ matrix
            for outlier in (None, 3):
                target = SOURCE @ matrix + np.array([14.5, -23.75])
                target += rng.uniform(-0.005, 0.005, size=target.shape)
                mask = np.ones(len(SOURCE), dtype=bool)
                if outlier is not None:
                    target[outlier] += [2.4, -1.9]
                    mask[outlier] = False
                case_id = f"{model}/{degrees}/{'outlier' if outlier is not None else 'clean'}"
                yield case_id, mask, dict(model=model, source=SOURCE.tolist(),
                                          target=target.tolist(), threshold=THRESHOLD_MM)


def check_fits():
    cases = list(registration_cases())
    results = node("tests/register-oracle", inputs=json.dumps([case for _, _, case in cases]))
    evidence = []
    for (name, expected_mask, case), result in zip(cases, results, strict=True):
        assert result is not None, name
        target = np.asarray(case["target"])
        matrix, translation = reference_fit(case["model"], SOURCE[expected_mask], target[expected_mask])
        residuals = np.linalg.norm(SOURCE @ matrix + translation - target, axis=1)
        np.testing.assert_array_equal(residuals <= THRESHOLD_MM, expected_mask, err_msg=name)
        np.testing.assert_array_equal(result["mask"], expected_mask, err_msg=name)
        inliers = residuals[expected_mask]
        rotation = np.rad2deg(np.arctan2(matrix[0, 1], matrix[0, 0]))
        expected = dict(matrix=matrix, translation=translation, residuals_mm=residuals,
                        rms_mm=np.sqrt(np.mean(inliers ** 2)), max_mm=inliers.max(),
                        rotation_deg=rotation, scale=np.sqrt(abs(np.linalg.det(matrix))))
        deltas = {}
        for field, value in expected.items():
            # Linear coefficients and scale are dimensionless; rotation is in degrees.
            bound = EPS_MM if field.endswith("_mm") or field == "translation" else 1e-10
            np.testing.assert_allclose(result[field], value, atol=bound, rtol=0, err_msg=f"{name}/{field}")
            deltas[field] = float(np.max(np.abs(result[field] - value)))
        evidence.append(dict(case=name, inliers=int(expected_mask.sum()), max_abs_delta=deltas))
    return evidence


def check_minimax():
    # Three boundary offsets at radius .05 mm enclose their known centre.
    # The offset mean is displaced, so a mean fit cannot pass just above .05 mm.
    centre = np.array([7.0, -9.0])
    offsets = centre + np.array([[0.05, 0], [-0.03, 0.04], [-0.03, -0.04]])
    baseline = np.array([(2, 3), (20, 4), (6, 23), (10, 13)], dtype=float)
    delivery = baseline - np.vstack((offsets, centre))
    convention = dict(unit="mm", bottom_x="direct", angle_sign=1,
                      top_angle_offset_deg=0, bottom_angle_offset_deg=0)
    policy = dict(baseline=convention, delivery=convention, anchors=["A1", "A2", "A3"],
                  rotation="0", position_tolerance_mm=0.1, angle_tolerance_deg=1)

    def write_csv(path, points):
        rows = [f"{ref},{x:.9f},{y:.9f},0,top\n"
                for ref, (x, y) in zip(("A1", "A2", "A3", "D1"), points, strict=True)]
        path.write_text("Ref,PosX,PosY,Rot,Side\n" + "".join(rows), encoding="utf-8")

    evidence = []
    with tempfile.TemporaryDirectory(prefix="moonplacement-minimax-") as work:
        base_path, delivery_path, policy_path = (Path(work) / name for name in ("base.csv", "delivery.csv", "policy.json"))
        write_csv(base_path, baseline)
        write_csv(delivery_path, delivery)
        for accepted, limit in [(False, 0.049999), (True, 0.050001)]:
            policy_path.write_text(json.dumps(dict(policy, anchor_tolerance_mm=limit)), encoding="utf-8")
            report = node("cmd/main", [base_path, delivery_path, policy_path], exit_code=0 if accepted else 2)
            assert report["status"] == ("pass" if accepted else "indeterminate"), report
            frame = report["frame"] if accepted else report["rejected_frames"][0]["frame"]
            shift = frame["delivery_to_baseline_mm"]
            np.testing.assert_allclose([shift["x"], shift["y"]], centre, atol=EPS_MM, rtol=0)
            np.testing.assert_allclose(frame["max_anchor_error_mm"], 0.05, atol=EPS_MM, rtol=0)
            np.testing.assert_allclose(
                [row["distance_mm"] for row in frame["anchor_residuals"]], [0.05] * 3, atol=EPS_MM, rtol=0,
            )
            evidence.append(dict(tolerance_mm=limit, status=report["status"],
                                 radius_mm=frame["max_anchor_error_mm"], translation_mm=shift))
    return evidence


if __name__ == "__main__":
    fits = check_fits()
    minimax = check_minimax()
    output = Path("_build/registration-oracle.json")
    output.write_text(json.dumps(dict(fits=fits, minimax=minimax), indent=2) + "\n", encoding="utf-8")
    print(f"{len(fits)} NumPy registration comparisons and {len(minimax)} CLI minimax boundary cases passed")
