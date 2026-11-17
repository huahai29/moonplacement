///|
fn sample_board() -> Array[Point] {
  [
    { x: 0.0, y: 0.0, },
    { x: 12.0, y: 0.0, },
    { x: 0.0, y: 9.0, },
    { x: 12.0, y: 9.0, },
    { x: 5.0, y: 4.0, },
    { x: 9.0, y: 7.0, },
  ]
}

///|
test "similarity registration recovers a known rotation, scale and translation" {
  let known = Transform2D::rotation(30.0, { x: 4.0, y: -2.0, }, scale=1.5)
  let source = sample_board()
  let target = source.map(point => known.apply(point))
  let registration = register(source, target, Similarity, 1.0e-9)
  guard! registration is Some(result)
  assert_true((result.rotation_deg - 30.0).abs() < 1.0e-9)
  assert_true((result.scale - 1.5).abs() < 1.0e-12)
  assert_true(result.rms_mm < 1.0e-9)
  assert_true(result.max_mm < 1.0e-9)
  assert_true(result.inlier_count() == 6)
}

///|
test "rigid registration pins the scale to one" {
  let known = Transform2D::rotation(-12.0, { x: 1.0, y: 1.0, })
  let source = sample_board()
  let target = source.map(point => known.apply(point))
  let registration = register(source, target, Rigid, 1.0e-9)
  guard! registration is Some(result)
  assert_true((result.rotation_deg + 12.0).abs() < 1.0e-9)
  assert_true((result.scale - 1.0).abs() < 1.0e-12)
}

///|
test "affine registration recovers a sheared map" {
  let known : Transform2D = {
    a: 1.02,
    b: 0.03,
    c: 1.0,
    d: -0.01,
    e: 0.98,
    f: -2.0,
  }
  let source = sample_board()
  let target = source.map(point => known.apply(point))
  let registration = register(source, target, Affine, 1.0e-9)
  guard! registration is Some(result)
  assert_true((result.transform.a - 1.02).abs() < 1.0e-9)
  assert_true((result.transform.b - 0.03).abs() < 1.0e-9)
  assert_true((result.transform.d + 0.01).abs() < 1.0e-9)
  assert_true((result.transform.e - 0.98).abs() < 1.0e-9)
  assert_true(result.rms_mm < 1.0e-9)
}

///|
test "robust registration discards one displaced anchor" {
  let known = Transform2D::rotation(5.0, { x: 2.0, y: 3.0, })
  let source = sample_board()
  let target : Array[Point] = []
  for i, point in source {
    let mapped = known.apply(point)
    if i == 2 {
      target.push({ x: mapped.x + 3.0, y: mapped.y - 2.0, })
    } else {
      target.push(mapped)
    }
  }
  let registration = register(source, target, Similarity, 0.05)
  guard! registration is Some(result)
  assert_true(result.inlier_count() == 5)
  assert_true(!result.inlier_mask[2])
  assert_true((result.rotation_deg - 5.0).abs() < 1.0e-6)
}

///|
test "affine registration rejects collinear anchors" {
  let source : Array[Point] = [
    { x: 0.0, y: 0.0, },
    { x: 5.0, y: 5.0, },
    { x: 10.0, y: 10.0, },
  ]
  let target = source.map(point => point)
  assert_true(register(source, target, Affine, 0.1) is None)
}

///|
test "audit accepts an identity similarity frame" {
  let board = fixture_table(
    "A,10,0,0,top\nB,30,0,90,top\nC,10,20,180,bottom\nD,19,13,355,bottom",
  )
  let rows = StringBuilder()
  for key in ["A", "B", "C", "D"] {
    let part = board.rows[key]
    let offset = if part.side == Top { 10.0 } else { -20.0 }
    let raw_angle = offset - part.angle_deg
    rows.write_string(
      "\{key},\{part.xy.x},\{part.xy.y},\{raw_angle},\{side_name(part.side)}\n",
    )
  }
  let result = audit(
    board,
    fixture_table(rows.to_string()),
    fixture_policy(alignment="similarity", bottom_x="direct"),
  )
  assert_true(result.verdict is Pass)
  guard! result.report
    is {
      "frame": {
        "rotation_deg": Number(deg, ..),
        "scale": Number(scale, ..),
        ..
      },
      ..
    }
  assert_true(deg.abs() < 1.0e-9)
  assert_true((scale - 1.0).abs() < 1.0e-12)
}

///|
test "audit recovers a continuous rotation and scale" {
  let board = fixture_table(
    "A,10,0,0,top\nB,30,0,90,top\nC,10,20,180,bottom\nD,19,13,355,bottom",
  )
  let phi = 3.7
  let factor = 1.0004
  let translation : Point = { x: 1.3, y: -0.7, }
  let inverse = Transform2D::rotation(
    -phi,
    { x: 0.0, y: 0.0, },
    scale=1.0 / factor,
  )
  let rows = StringBuilder()
  for key in ["A", "B", "C", "D"] {
    let part = board.rows[key]
    let delivery_xy = inverse.apply(difference(part.xy, translation))
    let offset = if part.side == Top { 10.0 } else { -20.0 }
    let raw_angle = offset - part.angle_deg + phi
    rows.write_string(
      "\{key},\{delivery_xy.x},\{delivery_xy.y},\{raw_angle},\{side_name(part.side)}\n",
    )
  }
  let result = audit(
    board,
    fixture_table(rows.to_string()),
    fixture_policy(alignment="similarity", bottom_x="direct"),
  )
  assert_true(result.verdict is Pass)
  guard! result.report
    is {
      "frame": {
        "rotation_deg": Number(deg, ..),
        "scale": Number(found, ..),
        ..
      },
      ..
    }
  assert_true((deg - phi).abs() < 1.0e-4)
  assert_true((found - factor).abs() < 1.0e-4)
}

///|
test "robust alignment isolates a displaced anchor instead of losing the board" {
  let board = fixture_table(
    "A,0,0,10,top\nB,10,0,10,top\nC,0,10,10,top\nD,10,10,10,top\nE,5,5,10,top",
  )
  let shifted = fixture_table(
    "A,0,0,0,top\nB,10,0,0,top\nC,3,10,0,top\nD,10,10,0,top\nE,5,5,0,top",
  )
  let enumerate = audit(
    board,
    shifted,
    fixture_policy(anchors=["A", "B", "C", "D"], bottom_x="direct"),
  )
  assert_true(enumerate.verdict is Indeterminate)
  let robust = audit(
    board,
    shifted,
    fixture_policy(
      anchors=["A", "B", "C", "D"],
      bottom_x="direct",
      alignment="similarity",
    ),
  )
  assert_true(robust.verdict is Different)
  assert_true(
    robust.report
    is {
      "differences": [{ "ref": String("C"), "kind": String("position"), .. }],
      ..
    },
  )
}

///|
test "configuration rejects an unknown alignment mode" {
  let result = Ok(fixture_policy(alignment="bogus")) catch {
    error => Err(error)
  }
  assert_true(result is Err(InvalidInput("alignment", _)))
}
