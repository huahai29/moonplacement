///|
test "circle area and containment" {
  let circle = Circle(2.0)
  assert_true((circle.area() - @math.PI * 4.0).abs() < 1.0e-12)
  assert_true(circle.contains({ x: 1.0, y: 1.0, }, { x: 2.0, y: 1.0, }))
  assert_true(!circle.contains({ x: 1.0, y: 1.0, }, { x: 3.5, y: 1.0, }))
}

///|
test "rectangle and obround containment" {
  let rectangle = Rectangle(4.0, 2.0)
  assert_true((rectangle.area() - 8.0).abs() < 1.0e-12)
  assert_true(rectangle.contains({ x: 0.0, y: 0.0, }, { x: 1.9, y: 0.9, }))
  assert_true(!rectangle.contains({ x: 0.0, y: 0.0, }, { x: 2.1, y: 0.0, }))
  let obround = Obround(4.0, 1.0)
  assert_true(obround.contains({ x: 0.0, y: 0.0, }, { x: 1.9, y: 0.2, }))
  assert_true(!obround.contains({ x: 0.0, y: 0.0, }, { x: 1.9, y: 0.6, }))
}

///|
test "regular polygon containment and area" {
  let hexagon = Polygon(1.0, 6)
  let expected = 3.0 * 3.0.sqrt() / 2.0
  assert_true((hexagon.area() - expected).abs() < 1.0e-12)
  assert_true(hexagon.contains({ x: 0.0, y: 0.0, }, { x: 0.9, y: 0.0, }))
  assert_true(!hexagon.contains({ x: 0.0, y: 0.0, }, { x: 0.95, y: 0.95, }))
}

///|
test "polygon area, centroid and containment" {
  let square : Array[Point] = [
    { x: 0.0, y: 0.0, },
    { x: 2.0, y: 0.0, },
    { x: 2.0, y: 2.0, },
    { x: 0.0, y: 2.0, },
  ]
  assert_true((polygon_area(square) - 4.0).abs() < 1.0e-12)
  let center = polygon_centroid(square)
  assert_true((center.x - 1.0).abs() < 1.0e-12)
  assert_true((center.y - 1.0).abs() < 1.0e-12)
  assert_true(polygon_contains(square, { x: 1.0, y: 1.0, }))
  assert_true(!polygon_contains(square, { x: 3.0, y: 1.0, }))
}
