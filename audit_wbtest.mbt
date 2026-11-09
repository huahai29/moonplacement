///|
fn fixture_policy(
  anchors~ : Array[String] = ["A", "B", "C"],
  rotation~ : String = "0",
  bottom_x~ : String = "auto",
) -> Policy raise InputError {
  let baseline : Json = {
    "unit": Json("mm"),
    "bottom_x": Json("direct"),
    "angle_sign": Json(1),
    "top_angle_offset_deg": Json(0),
    "bottom_angle_offset_deg": Json(0),
  }
  let delivery : Json = {
    "unit": Json("mm"),
    "bottom_x": Json(bottom_x),
    "angle_sign": Json(-1),
    "top_angle_offset_deg": Json(10),
    "bottom_angle_offset_deg": Json(-20),
  }
  let policy : Json = {
    "baseline": baseline,
    "delivery": delivery,
    "anchors": Json(anchors),
    "rotation": Json(rotation),
    "position_tolerance_mm": Json(0.1),
    "angle_tolerance_deg": Json(1),
    "anchor_tolerance_mm": Json(0.02),
  }
  read_policy(policy.stringify())
}

///|
fn fixture_table(rows : String) -> PlacementTable raise InputError {
  read_placements("Ref,PosX,PosY,Rot,Side\n" + rows, source="fixture")
}

///|
test "all quarter-turns recovered with signed angle calibration and non-anchor holdout" {
  let baseline = fixture_table(
    "A,10,0,0,top\nB,30,0,90,top\nC,10,20,180,bottom\nD,19,13,355,bottom",
  )
  for turns in 0..<4 {
    let rows = StringBuilder()
    for key in ["A", "B", "C", "D"] {
      let part = baseline.rows[key]
      let shifted = difference(part.xy, { x: 2.0, y: 4.0, })
      let local_xy = rotation(shifted, (4 - turns) % 4)
      let offset = if part.side == Top { 10.0 } else { -20.0 }
      let raw_angle = offset + (turns * 90).to_double() - part.angle_deg
      let raw_x = if part.side == Bottom { -local_xy.x } else { local_xy.x }
      rows.write_string(
        "\{key},\{raw_x},\{local_xy.y},\{raw_angle},\{side_name(part.side)}\n",
      )
    }
    let result = audit(
      baseline,
      fixture_table(rows.to_string()),
      fixture_policy(rotation="auto"),
    )
    assert_true(result.verdict is Pass)
    guard! result.report
      is {
        "frame": {
          "rotation_deg": Number(deg, ..),
          "delivery_bottom_x": String("negated"),
          ..
        },
        ..
      }
    assert_eq(deg, (turns * 90).to_double())
  }
}

///|
test "no-angle evidence when a component is assigned to the wrong side" {
  let baseline = fixture_table(
    "A,0,0,10,top\nB,10,0,10,top\nC,0,10,10,top\nD,5,5,10,top",
  )
  let delivery = fixture_table(
    "A,0,0,0,top\nB,10,0,0,top\nC,0,10,0,top\nD,15,15,100,bottom",
  )
  let result = audit(baseline, delivery, fixture_policy(bottom_x="direct"))
  assert_true(result.verdict is Different)
  assert_true(
    result.report
    is {
      "differences": [{ "ref": String("D"), "kind": String("side"), .. }],
      ..
    },
  )
}

///|
test "coincident and near-collinear anchors are indeterminate" {
  for c in ["C,0,0,0,top", "C,20,0.01,0,top"] {
    let board = fixture_table("A,0,0,0,top\nB,10,0,0,top\n\{c}\nD,5,5,0,top")
    let result = audit(board, board, fixture_policy())
    assert_true(result.verdict is Indeterminate)
    assert_true(
      result.report is { "reason": String("degenerate_baseline_anchors"), .. },
    )
  }
}

///|
test "missing and side-mismatched anchors carry distinct evidence" {
  let baseline = fixture_table("A,0,0,0,top\nB,10,0,0,top\nC,0,10,0,top")
  let delivery = fixture_table("A,0,0,0,top\nB,10,0,0,bottom")
  let result = audit(baseline, delivery, fixture_policy())
  assert_true(result.verdict is Indeterminate)
  assert_true(
    result.report
    is {
      "reason": String("invalid_anchors"),
      "differences": [
        { "ref": String("B"), "kind": String("anchor_side"), .. },
        { "ref": String("C"), "kind": String("anchor_missing_delivery"), .. },
      ],
      ..
    },
  )
}

///|
test "all-anchor datasets cannot pass without a holdout" {
  let baseline = fixture_table("A,0,0,10,top\nB,10,0,10,top\nC,0,10,10,top")
  let delivery = fixture_table("A,0,0,0,top\nB,10,0,0,top\nC,0,10,0,top")
  let result = audit(baseline, delivery, fixture_policy())
  assert_true(result.verdict is Indeterminate)
  assert_true(
    result.report is { "reason": String("no_independent_components"), .. },
  )
}

///|
test "wrong declared reflection cannot produce a pass" {
  let baseline = fixture_table(
    "A,0,0,10,top\nB,10,0,10,top\nC,5,10,-20,bottom\nD,7,5,-20,bottom",
  )
  let delivery = fixture_table(
    "A,0,0,0,top\nB,10,0,0,top\nC,-5,10,0,bottom\nD,-7,5,0,bottom",
  )
  let result = audit(baseline, delivery, fixture_policy(bottom_x="direct"))
  assert_true(result.verdict is Indeterminate)
  assert_true(
    result.report
    is {
      "reason": String("no_matching_frame"),
      "rejected_frames": [{ "reason": String("anchor_tolerance_exceeded"), .. }],
      ..
    },
  )
}

///|
test "configuration rejects duplicate anchors and unsupported rotation" {
  let duplicates = Ok(fixture_policy(anchors=["A", " a ", "C"])) catch {
    error => Err(error)
  }
  assert_true(duplicates is Err(InvalidInput("anchors", _)))
  let rotation = Ok(fixture_policy(rotation="45")) catch { error => Err(error) }
  assert_true(rotation is Err(InvalidInput("rotation", _)))
}
