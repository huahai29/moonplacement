///|
test "two support points determine the center for an obtuse triangle" {
  let center = minimax_translation([
    { x: 10.0, y: -3.0, },
    { x: 14.0, y: -3.0, },
    { x: 11.0, y: -2.9, },
  ])
  assert_eq(center.x, 12.0)
  assert_eq(center.y, -3.0)
}

///|
test "three support points determine the center for an acute triangle" {
  // Symmetry gives x = 2. Equating the distance to (0, 0) and (2, 3)
  // gives y = 5/6 and a radius of 13/6.
  let points : Array[Point] = [
    { x: 0.0, y: 0.0, },
    { x: 4.0, y: 0.0, },
    { x: 2.0, y: 3.0, },
  ]
  for order in [[0, 1, 2], [2, 0, 1], [1, 0, 2]] {
    let center = minimax_translation(order.map(i => points[i]))
    assert_true((center.x - 2.0).abs() < 1.0e-12)
    assert_true((center.y - 5.0 / 6.0).abs() < 1.0e-12)
    for point in points {
      assert_true(
        (magnitude(difference(point, center)) - 13.0 / 6.0).abs() < 1.0e-12,
      )
    }
  }
}

///|
test "small offsets retain a meaningful radius" {
  let center = minimax_translation([
    { x: 0.0, y: 0.0, },
    { x: 2.0e-200, y: 0.0, },
    { x: 0.0, y: 0.0, },
  ])
  assert_eq(center.x, 1.0e-200)
  assert_eq(magnitude(center), 1.0e-200)
}
