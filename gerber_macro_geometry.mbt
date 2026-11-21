///|
fn thermal_quadrant(radius : Double, gap : Double) -> Double {
  if radius <= gap * 2.0.sqrt() {
    return 0.0
  }
  let g = gap / radius
  radius *
  radius *
  (@math.acos(g) - @math.PI * 0.25 - g * (1.0 - g * g).sqrt() + g * g)
}

///|
fn turn(a : Point, b : Point, c : Point) -> Double {
  (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

///|
fn outline_edges_touch(a : Point, b : Point, c : Point, d : Point) -> Bool {
  if a.x.max(b.x) < c.x.min(d.x) ||
    c.x.max(d.x) < a.x.min(b.x) ||
    a.y.max(b.y) < c.y.min(d.y) ||
    c.y.max(d.y) < a.y.min(b.y) {
    return false
  }
  let ab_c = turn(a, b, c)
  let ab_d = turn(a, b, d)
  let cd_a = turn(c, d, a)
  let cd_b = turn(c, d, b)
  ((ab_c <= 0.0 && ab_d >= 0.0) || (ab_c >= 0.0 && ab_d <= 0.0)) &&
  ((cd_a <= 0.0 && cd_b >= 0.0) || (cd_a >= 0.0 && cd_b <= 0.0))
}

///|
fn outline_macro(
  fields : Array[Double],
  count : Double,
  unit : Double,
  source : String,
  name : String,
) -> (Shape, Point, Double) raise GerberError {
  let invalid = InvalidGerber(
    source,
    "无效、不闭合或自交的光圈宏轮廓：\{name}",
  )
  if count < 3.0 || count > 5000.0 || count != count.to_int().to_double() {
    raise invalid
  }
  let n = count.to_int()
  if fields.length() != 6 + 2 * n ||
    fields[3] != fields[3 + 2 * n] ||
    fields[4] != fields[4 + 2 * n] {
    raise invalid
  }
  let origin : Point = { x: fields[3] * unit, y: fields[4] * unit, }
  let points : Array[Point] = []
  for i in 0..<n {
    points.push({
      x: (fields[3 + 2 * i] - fields[3]) * unit,
      y: (fields[4 + 2 * i] - fields[4]) * unit,
    })
  }
  for i in 0..<n {
    let a = points[i]
    let b = points[(i + 1) % n]
    let c = points[(i + 2) % n]
    if same_point(a, b) ||
      (
        turn(a, b, c) == 0.0 &&
        (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y) < 0.0
      ) {
      raise invalid
    }
    for j in (i + 2)..<n {
      if i == 0 && j == n - 1 {
        continue
      }
      if outline_edges_touch(a, b, points[j], points[(j + 1) % n]) {
        raise invalid
      }
    }
  }
  let area = polygon_area(points).abs()
  if !(area > 0.0) || area.is_inf() {
    raise invalid
  }
  let center = polygon_centroid(points)
  (
    Outline(points.map(p => difference(p, center))),
    { x: origin.x + center.x, y: origin.y + center.y, },
    fields[fields.length() - 1],
  )
}

///|
fn punched_macro(
  shape : Shape,
  solid : Point,
  angle : Double,
  cuts : ArrayView[Array[Double]],
  unit : Double,
  source : String,
  name : String,
) -> Aperture raise GerberError {
  let invalid = InvalidGerber(
    source,
    "暂不支持该多图元光圈宏：\{name}",
  )
  if cuts.length() > 64 {
    raise invalid
  }
  let holes : Array[(Point, Double)] = []
  let mut area = shape.area()
  let mut mx = 0.0
  let mut my = 0.0
  for cut in cuts {
    guard cut is [1.0, 0.0, diameter, x, y, .. trailing] &&
      trailing.length() <= 1 else {
      raise invalid
    }
    let absolute = aperture_rotation(trailing.get(0).unwrap_or(0.0)).apply({
      x: x * unit,
      y: y * unit,
    })
    let hole_center = aperture_rotation(-angle).apply(
      difference(absolute, solid),
    )
    let radius = diameter * unit * 0.5
    if !(radius > 0.0 && radius < hole_clearance(shape, hole_center)) {
      raise InvalidGerber(
        source,
        "圆孔必须有正直径且完全位于光圈内部：\{name}",
      )
    }
    if holes.any(hole => {
        magnitude(difference(hole_center, hole.0)) <= radius + hole.1
      }) {
      raise InvalidGerber(
        source,
        "暂不支持相交或相切的宏内圆孔：\{name}",
      )
    }
    let removed = @math.PI * radius * radius
    area -= removed
    mx -= removed * hole_center.x
    my -= removed * hole_center.y
    holes.push((hole_center, radius))
  }
  if !(area > 0.0) ||
    area.is_inf() ||
    mx.is_nan() ||
    mx.is_inf() ||
    my.is_nan() ||
    my.is_inf() {
    raise invalid
  }
  let center : Point = { x: mx / area, y: my / area, }
  let rotation = aperture_rotation(angle)
  let offset = rotation.apply(center)
  {
    shape: transform_shape(
      Punched(
        shape,
        { x: -center.x, y: -center.y, },
        holes.map(hole => (difference(hole.0, center), hole.1)),
      ),
      rotation,
    ),
    offset: { x: solid.x + offset.x, y: solid.y + offset.y, },
    can_draw: false,
  }
}
