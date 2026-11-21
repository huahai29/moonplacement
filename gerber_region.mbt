///|
/// Closed outlines filled independently. Retraced cut-ins within an outline
/// cancel under parity; a separate contour never subtracts from another.
pub struct GerberRegion {
  contours : Array[GerberContour]
  bounds : GerberBounds
}

///|
pub struct GerberContour {
  points : Array[Point]
  error : Double
  bounds : GerberBounds
}

///|
fn same_point(a : Point, b : Point) -> Bool {
  a.x == b.x && a.y == b.y
}

///|
fn segment_distance(point : Point, a : Point, b : Point) -> Double {
  let edge = difference(b, a)
  let p = difference(point, a)
  let length = magnitude(edge)
  if length == 0.0 {
    return magnitude(p)
  }
  let x = edge.x / length
  let y = edge.y / length
  let t = (p.x * x + p.y * y).max(0.0).min(length)
  @math.hypot(p.x - t * x, p.y - t * y)
}

///|
fn GerberContour::near_edge(
  self : GerberContour,
  point : Point,
  margin : Double,
) -> Bool {
  for i in 1..<self.points.length() {
    if segment_distance(point, self.points[i - 1], self.points[i]) <= margin {
      return true
    }
  }
  false
}

///|
fn GerberRegion::covers(self : GerberRegion, point : Point) -> Bool {
  self.contours.any(contour => {
    contour.bounds.overlaps(bounds_at(point, 0.0)) &&
    polygon_contains(contour.points, point) &&
    (contour.error == 0.0 || !contour.near_edge(point, contour.error))
  })
}

///|
fn GerberRegion::may_cover(
  self : GerberRegion,
  point : Point,
  margin : Double,
) -> Bool {
  let search = bounds_at(point, margin)
  self.bounds.overlaps(search) &&
  self.contours.any(contour => {
    contour.bounds.overlaps(search) &&
    (
      polygon_contains(contour.points, point) ||
      contour.near_edge(point, margin + contour.error)
    )
  })
}

///|
fn append_region_arc(
  points : Array[Point],
  arc : GerberArc,
  end : Point,
) -> Double {
  // Aim for a 1 µm sagitta. Cap subdivisions, then compute the actual
  // conservative error for the chosen subdivision and endpoint rounding.
  let target_step = (8.0 * 0.001 / arc.radius).sqrt().min(@math.PI / 4.0)
  let steps = @math.ceil(arc.sweep / target_step).min(1024.0).to_int().max(2)
  let angle = arc.sweep / steps.to_double()
  let start = @math.atan2(arc.start_vector.y, arc.start_vector.x)
  let step = if arc.clockwise { -angle } else { angle }
  for i in 1..<steps {
    let theta = start + step * i.to_double()
    points.push({
      x: arc.center.x + arc.radius * @math.cos(theta),
      y: arc.center.y + arc.radius * @math.sin(theta),
    })
  }
  points.push(end)
  let sine = @math.sin(angle * 0.25)
  2.0 * arc.radius * sine * sine + 2.0 * arc.deviation
}

///|
fn close_region_contour(
  state : GerberState,
  source : String,
) -> Unit raise GerberError {
  let points = state.region_points
  guard points.get(0) is Some(first) &&
    points.get(points.length() - 1) is Some(last) &&
    points.length() >= 4 &&
    same_point(first, last) else {
    raise InvalidGerber(
      source, "铜区轮廓必须闭合且至少包含三条离散边",
    )
  }
  let error = state.region_error
  let mut bounds = bounds_at(first, error)
  for p in points {
    bounds = bounds.union(bounds_at(p, error))
  }
  if polygon_area(points.map(p => difference(p, first))) == 0.0 {
    raise InvalidGerber(source, "铜区轮廓未围出有效面积")
  }
  state.region_contours.push({ points, error, bounds, })
  state.region_points = []
  state.region_error = 0.0
}
