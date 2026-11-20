///|
fn same_xy(p : Point, x : Double, y : Double) -> Bool {
  p.x == x && p.y == y
}

///|
fn rounded_macro(
  name : String,
  primitives : Array[Array[Double]],
  unit : Double,
  source : String,
) -> Aperture raise GerberError {
  let unsupported = InvalidGerber(
    source,
    "暂不支持该多图元光圈宏：\{name}",
  )
  if primitives.length() != 9 {
    raise unsupported
  }
  let mut outline = None
  for primitive in primitives {
    if primitive
      is [4.0, 1.0, 4.0, x0, y0, x1, y1, x2, y2, x3, y3, end_x, end_y, 0.0] &&
      x0 == end_x &&
      y0 == end_y &&
      outline is None {
      outline = Some([
        { x: x0, y: y0, },
        { x: x1, y: y1, },
        { x: x2, y: y2, },
        { x: x3, y: y3, },
      ])
    }
  }
  guard outline is Some(corners) else { raise unsupported }
  let circles = Array::make(4, false)
  let strips = Array::make(4, false)
  let mut diameter = 0.0
  for primitive in primitives {
    match primitive {
      [4.0, ..] => ()
      [1.0, 1.0, width, x, y, .. rotation] if rotation.is_empty() ||
        rotation is [0.0] => {
        let mut matched = false
        for i, corner in corners {
          if !circles[i] && same_xy(corner, x, y) {
            circles[i] = true
            matched = true
            break
          }
        }
        if !matched || width <= 0.0 || (diameter != 0.0 && diameter != width) {
          raise unsupported
        }
        diameter = width
      }
      [20.0, 1.0, width, ax, ay, bx, by, 0.0] => {
        let mut matched = false
        for i, a in corners {
          let b = corners[(i + 1) % 4]
          if !strips[i] &&
            (
              (same_xy(a, ax, ay) && same_xy(b, bx, by)) ||
              (same_xy(a, bx, by) && same_xy(b, ax, ay))
            ) {
            strips[i] = true
            matched = true
            break
          }
        }
        if !matched || width <= 0.0 || (diameter != 0.0 && diameter != width) {
          raise unsupported
        }
        diameter = width
      }
      _ => raise unsupported
    }
  }
  if !circles.iter().all(value => value) || !strips.iter().all(value => value) {
    raise unsupported
  }
  let origin = corners[0]
  let mut vertices = corners.map(p => {
    x: (p.x - origin.x) * unit,
    y: (p.y - origin.y) * unit,
  })
  if polygon_area(vertices) < 0.0 {
    vertices = [vertices[0], vertices[3], vertices[2], vertices[1]]
  }
  // Require a strictly convex outline. Only then do the strips and circles
  // describe exactly the disk offset of the quadrilateral.
  let normals : Array[Point] = []
  let lengths = []
  for i in 0..<4 {
    let a = vertices[i]
    let b = vertices[(i + 1) % 4]
    let c = vertices[(i + 2) % 4]
    let dx = b.x - a.x
    let dy = b.y - a.y
    let turn = dx * (c.y - b.y) - dy * (c.x - b.x)
    let length = @math.hypot(dx, dy)
    if turn <= 0.0 ||
      turn.is_nan() ||
      turn.is_inf() ||
      length == 0.0 ||
      length.is_inf() {
      raise unsupported
    }
    normals.push({ x: dy / length, y: -dx / length, })
    lengths.push(length)
  }
  let radius = diameter * unit * 0.5
  if radius == 0.0 || radius.is_inf() {
    raise unsupported
  }
  let (center, area) = rounded_moments(vertices, lengths, normals, radius)
  let offset : Point = {
    x: origin.x * unit + center.x,
    y: origin.y * unit + center.y,
  }
  if area <= 0.0 ||
    area.is_inf() ||
    area.is_nan() ||
    offset.x.is_inf() ||
    offset.x.is_nan() ||
    offset.y.is_inf() ||
    offset.y.is_nan() {
    raise unsupported
  }
  {
    shape: RoundedOutline(
      vertices.map(p => { x: p.x - center.x, y: p.y - center.y, }),
      radius,
    ),
    offset,
    can_draw: false,
  }
}

///|
fn rounded_moments(
  vertices : Array[Point],
  lengths : Array[Double],
  normals : Array[Point],
  radius : Double,
) -> (Point, Double) {
  // Integrate disjoint areas: core polygon, exterior strips, exterior sectors.
  // The relative sector moments cancel over the full turn of the normals.
  let mut area = 0.0
  let mut mx = 0.0
  let mut my = 0.0
  for i in 0..<4 {
    let a = vertices[i]
    let b = vertices[(i + 1) % 4]
    let normal = normals[i]
    let previous = normals[(i + 3) % 4]
    let triangle = (a.x * b.y - a.y * b.x) * 0.5
    let strip = lengths[i] * radius
    let angle = @math.atan2(
      previous.x * normal.y - previous.y * normal.x,
      previous.x * normal.x + previous.y * normal.y,
    )
    let sector = radius * radius * angle * 0.5
    area += triangle + strip + sector
    mx += triangle * ((a.x + b.x) / 3.0) +
      strip * ((a.x + b.x + radius * normal.x) * 0.5) +
      sector * a.x
    my += triangle * ((a.y + b.y) / 3.0) +
      strip * ((a.y + b.y + radius * normal.y) * 0.5) +
      sector * a.y
  }
  ({ x: mx / area, y: my / area, }, area)
}
