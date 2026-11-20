///|
/// Circular centerline and stroke radius. The deviation bounds the effect
/// of unequal endpoint radii in a rounded Gerber export.
pub struct GerberArc {
  center : Point
  start_vector : Point
  end_vector : Point
  clockwise : Bool
  sweep : Double
  radius : Double
  deviation : Double
  stroke_radius : Double
}

///|
fn directed_angle(from : Point, to : Point, clockwise : Bool) -> Double {
  let cross = from.x * to.y - from.y * to.x
  let dot = from.x * to.x + from.y * to.y
  let angle = @math.atan2(if clockwise { -cross } else { cross }, dot)
  if angle < 0.0 {
    angle + 2.0 * @math.PI
  } else {
    angle
  }
}

///|
fn make_gerber_arc(
  start : Point,
  end : Point,
  offset : Point,
  clockwise : Bool,
  stroke_radius : Double,
  source : String,
) -> GerberArc raise GerberError {
  let center : Point = { x: start.x + offset.x, y: start.y + offset.y, }
  // Form both vectors in the start-relative frame, so a large board
  // translation does not cause avoidable cancellation at the start.
  let a : Point = { x: -offset.x, y: -offset.y, }
  let b = difference(difference(end, start), offset)
  let radius = magnitude(a)
  let end_radius = magnitude(b)
  let full_circle = start.x == end.x && start.y == end.y
  let sweep = if full_circle {
    2.0 * @math.PI
  } else {
    directed_angle(a, b, clockwise)
  }
  if radius <= 0.0 ||
    end_radius <= 0.0 ||
    sweep <= 0.0 ||
    (!full_circle && sweep >= 2.0 * @math.PI) {
    raise InvalidGerber(source, "圆弧缺少有效的 I/J 偏移或终点")
  }
  let error_scale = radius
    .max(end_radius)
    .max(start.x.abs())
    .max(start.y.abs())
    .max(end.x.abs())
    .max(end.y.abs())
  let deviation = (radius - end_radius).abs() + error_scale * 4.0e-15
  {
    center,
    start_vector: a,
    end_vector: { x: b.x / end_radius * radius, y: b.y / end_radius * radius, },
    clockwise,
    sweep,
    radius,
    deviation,
    stroke_radius,
  }
}

///|
fn GerberArc::distance(self : GerberArc, point : Point) -> Double {
  let vector = difference(point, self.center)
  if self.sweep == 2.0 * @math.PI ||
    directed_angle(self.start_vector, vector, self.clockwise) <= self.sweep {
    (magnitude(vector) - self.radius).abs()
  } else {
    magnitude(difference(vector, self.start_vector)).min(
      magnitude(difference(vector, self.end_vector)),
    )
  }
}

///|
fn GerberArc::bounds(self : GerberArc) -> GerberBounds {
  bounds_at(self.center, self.radius + self.stroke_radius + self.deviation)
}

///|
fn GerberArc::may_cover(
  self : GerberArc,
  point : Point,
  margin : Double,
) -> Bool {
  self.stroke_radius > 0.0 &&
  self.distance(point) <= self.stroke_radius + margin + self.deviation
}

///|
fn GerberArc::covers(self : GerberArc, point : Point, margin : Double) -> Bool {
  self.stroke_radius > 0.0 &&
  self.distance(point) + self.deviation <= self.stroke_radius + margin
}
