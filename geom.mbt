///|
/// A centered pad aperture. All parameters are in millimetres.
///
/// Gerber `C`, `R`, `O` and `P` apertures map directly onto these variants; the
/// same shapes are reused by the geometry checks so parsing and verification
/// share one area/containment implementation.
pub enum Shape {
  /// Radius.
  Circle(Double)
  /// Width and height.
  Rectangle(Double, Double)
  /// Width and height of the stadium.
  Obround(Double, Double)
  /// Circumradius and vertex count.
  Polygon(Double, Int32)
}

///|
pub fn Shape::area(self : Shape) -> Double {
  match self {
    Circle(radius) => @math.PI * radius * radius
    Rectangle(width, height) => width * height
    Obround(width, height) => {
      let long = width.max(height)
      let short = width.min(height)
      (long - short) * short + @math.PI * short * short / 4.0
    }
    Polygon(radius, sides) => {
      let count = sides.to_double()
      0.5 * count * radius * radius * @math.sin(2.0 * @math.PI / count)
    }
  }
}

///|
fn is_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn digit_value(ch : Char) -> Int32 {
  ch.to_int() - 48
}

///|
fn polygon_vertices(radius : Double, sides : Int32) -> Array[Point] {
  let vertices : Array[Point] = []
  if sides < 3 {
    return vertices
  }
  let step = 2.0 * @math.PI / sides.to_double()
  for i in 0..<sides {
    let angle = step * i.to_double()
    vertices.push({
      x: radius * @math.cos(angle),
      y: radius * @math.sin(angle),
    })
  }
  vertices
}

///|
fn obround_contains(
  width : Double,
  height : Double,
  dx : Double,
  dy : Double,
) -> Bool {
  let long = width.max(height)
  let short = width.min(height)
  let radius = short * 0.5
  let straight = long * 0.5 - radius
  let (along, across) = if width >= height { (dx, dy) } else { (dy, dx) }
  if along.abs() <= straight {
    return across.abs() <= radius
  }
  let center = if along > 0.0 { straight } else { -straight }
  let offset = along - center
  offset * offset + across * across <= radius * radius
}

///|
fn convex_contains(vertices : Array[Point], point : Point) -> Bool {
  if vertices.length() < 3 {
    return false
  }
  let mut sign = 0.0
  for i in 0..<vertices.length() {
    let a = vertices[i]
    let b = vertices[(i + 1) % vertices.length()]
    let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
    if cross == 0.0 {
      continue
    }
    if sign == 0.0 {
      sign = cross
    } else if sign * cross < 0.0 {
      return false
    }
  }
  true
}

///|
/// Grow the shape by `amount` on every side. Used to test a point against a pad
/// with a tolerance instead of treating a near miss as empty copper.
pub fn Shape::expanded(self : Shape, amount : Double) -> Shape {
  match self {
    Circle(radius) => Circle(radius + amount)
    Rectangle(width, height) =>
      Rectangle(width + 2.0 * amount, height + 2.0 * amount)
    Obround(width, height) =>
      Obround(width + 2.0 * amount, height + 2.0 * amount)
    Polygon(radius, sides) => Polygon(radius + amount, sides)
  }
}

///|
/// Whether `point` lies inside the shape centered at `center`.
pub fn Shape::contains(self : Shape, center : Point, point : Point) -> Bool {
  let dx = point.x - center.x
  let dy = point.y - center.y
  match self {
    Circle(radius) => dx * dx + dy * dy <= radius * radius
    Rectangle(width, height) =>
      dx.abs() <= width * 0.5 && dy.abs() <= height * 0.5
    Obround(width, height) => obround_contains(width, height, dx, dy)
    Polygon(radius, sides) => {
      let vertices = polygon_vertices(radius, sides)
      let moved = vertices.map(v => { x: v.x - dx, y: v.y - dy, })
      convex_contains(moved, { x: 0.0, y: 0.0, })
    }
  }
}

///|
/// Signed area of a closed polygon (shoelace formula). Positive for a
/// counter-clockwise ring.
pub fn polygon_area(points : Array[Point]) -> Double {
  let count = points.length()
  if count < 3 {
    return 0.0
  }
  let mut twice = 0.0
  for i in 0..<count {
    let a = points[i]
    let b = points[(i + 1) % count]
    twice += a.x * b.y - b.x * a.y
  }
  twice * 0.5
}

///|
pub fn polygon_centroid(points : Array[Point]) -> Point {
  let count = points.length()
  let mut area = 0.0
  let mut x = 0.0
  let mut y = 0.0
  for i in 0..<count {
    let a = points[i]
    let b = points[(i + 1) % count]
    let cross = a.x * b.y - b.x * a.y
    area += cross
    x += (a.x + b.x) * cross
    y += (a.y + b.y) * cross
  }
  if area == 0.0 {
    return { x: 0.0, y: 0.0, }
  }
  { x: x / (3.0 * area), y: y / (3.0 * area), }
}

///|
/// Ray-casting containment test for an arbitrary simple polygon.
pub fn polygon_contains(points : Array[Point], point : Point) -> Bool {
  let count = points.length()
  if count < 3 {
    return false
  }
  let mut inside = false
  let mut j = count - 1
  for i in 0..<count {
    let a = points[i]
    let b = points[j]
    if (a.y > point.y) != (b.y > point.y) {
      let x = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
      if point.x < x {
        inside = !inside
      }
    }
    j = i
  }
  inside
}
