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
  /// A centered aperture under a rotation, reflection, or uniform scale.
  Transformed(Shape, Transform2D)
  /// Convex outline relative to the copper centroid and its rounding radius.
  RoundedOutline(Array[Point], Double)
  /// Solid shape, outer center, hole center (both relative to the copper
  /// centroid), and hole radius in mm.
  RoundHole(Shape, Point, Point, Double)
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
    RoundedOutline(vertices, radius) => rounded_outline_area(vertices, radius)
    RoundHole(shape, _, _, radius) =>
      shape.area() - @math.PI * radius.max(0.0) * radius.max(0.0)
    Transformed(shape, matrix) => shape.area() * matrix.determinant().abs()
  }
}

///|
/// Radius of a circle enclosing this centered shape.
fn Shape::bounding_radius(self : Shape) -> Double {
  match self {
    Circle(radius) | Polygon(radius, _) => radius
    Rectangle(width, height) => @math.hypot(width * 0.5, height * 0.5)
    Obround(width, height) => width.max(height) * 0.5
    RoundedOutline(vertices, radius) => {
      let mut result = 0.0
      for p in vertices {
        result = result.max(@math.hypot(p.x, p.y))
      }
      result + radius
    }
    Transformed(shape, matrix) => shape.bounding_radius() * matrix.scale()
    RoundHole(shape, outer, _, _) =>
      shape.bounding_radius() + @math.hypot(outer.x, outer.y)
  }
}

///|
/// World-space disk that the aperture does not paint, including under LPC.
fn Shape::transparent_hole(self : Shape, center : Point) -> (Point, Double)? {
  match self {
    RoundHole(_, _, hole, radius) =>
      Some(({ x: center.x + hole.x, y: center.y + hole.y, }, radius))
    Transformed(shape, matrix) => {
      guard shape.transparent_hole({ x: 0.0, y: 0.0, }) is Some((hole, radius)) else {
        return None
      }
      let offset = matrix.apply(hole)
      Some(
        (
          { x: center.x + offset.x, y: center.y + offset.y, },
          radius * matrix.scale(),
        ),
      )
    }
    _ => None
  }
}

///|
pub struct GerberBounds {
  lower : Point
  upper : Point
}

///|
fn bounds_at(at : Point, radius : Double) -> GerberBounds {
  {
    lower: { x: at.x - radius, y: at.y - radius, },
    upper: { x: at.x + radius, y: at.y + radius, },
  }
}

///|
fn GerberBounds::union(
  self : GerberBounds,
  other : GerberBounds,
) -> GerberBounds {
  {
    lower: {
      x: self.lower.x.min(other.lower.x),
      y: self.lower.y.min(other.lower.y),
    },
    upper: {
      x: self.upper.x.max(other.upper.x),
      y: self.upper.y.max(other.upper.y),
    },
  }
}

///|
fn GerberBounds::overlaps(self : GerberBounds, other : GerberBounds) -> Bool {
  self.lower.x <= other.upper.x &&
  other.lower.x <= self.upper.x &&
  self.lower.y <= other.upper.y &&
  other.lower.y <= self.upper.y
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
    RoundedOutline(vertices, radius) =>
      RoundedOutline(vertices, radius + amount)
    RoundHole(shape, outer, hole, radius) =>
      RoundHole(shape.expanded(amount), outer, hole, radius - amount)
    Transformed(shape, matrix) =>
      Transformed(shape.expanded(amount / matrix.scale()), matrix)
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
    RoundedOutline(vertices, radius) =>
      rounded_outline_contains(vertices, radius, { x: dx, y: dy, })
    RoundHole(shape, outer, hole, radius) =>
      (radius <= 0.0 || @math.hypot(dx - hole.x, dy - hole.y) >= radius) &&
      shape.contains(outer, { x: dx, y: dy, })
    Transformed(shape, matrix) => {
      let determinant = matrix.determinant()
      if determinant == 0.0 {
        return false
      }
      shape.contains({ x: 0.0, y: 0.0, }, {
        x: (matrix.e * dx - matrix.b * dy) / determinant,
        y: (matrix.a * dy - matrix.d * dx) / determinant,
      })
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

///|
fn rounded_outline_area(vertices : Array[Point], radius : Double) -> Double {
  let mut perimeter = 0.0
  for i, a in vertices {
    let b = vertices[(i + 1) % vertices.length()]
    perimeter += @math.hypot(b.x - a.x, b.y - a.y)
  }
  polygon_area(vertices).abs() + perimeter * radius + @math.PI * radius * radius
}

///|
fn rounded_outline_contains(
  vertices : Array[Point],
  radius : Double,
  point : Point,
) -> Bool {
  if convex_contains(vertices, point) {
    return true
  }
  for i, a in vertices {
    let b = vertices[(i + 1) % vertices.length()]
    let dx = b.x - a.x
    let dy = b.y - a.y
    let length = @math.hypot(dx, dy)
    if length == 0.0 {
      continue
    }
    let ux = dx / length
    let uy = dy / length
    let px = point.x - a.x
    let py = point.y - a.y
    let along = (px * ux + py * uy).max(0.0).min(length)
    if @math.hypot(px - along * ux, py - along * uy) <= radius {
      return true
    }
  }
  false
}
