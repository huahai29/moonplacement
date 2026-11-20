///|
/// A dark, flashed pad extracted from a Gerber layer.
pub struct CopperPad {
  refdes : String?
  shape : Shape
  center : Point
  area : Double
}

///|
/// Extract the flashed dark pads from a parsed layer.
pub fn gerber_pads(document : GerberDocument) -> Array[CopperPad] {
  let pads : Array[CopperPad] = []
  for feature in document.features {
    if feature.dark {
      match feature.kind {
        Flash(shape, center) =>
          pads.push({
            refdes: feature.refdes,
            shape,
            center,
            area: shape.area(),
          })
        _ => ()
      }
    }
  }
  pads
}

///|
/// Group pads by their X2 component reference.
pub fn pad_groups(pads : Array[CopperPad]) -> Map[String, Array[CopperPad]] {
  let groups : Map[String, Array[CopperPad]] = Map([])
  for pad in pads {
    match pad.refdes {
      Some(reference) => {
        let key = designator(reference)
        match groups.get(key) {
          Some(group) => group.push(pad)
          None => groups[key] = [pad]
        }
      }
      None => ()
    }
  }
  groups
}

///|
/// Area-weighted centre of a pad group. This is a geometric reference, which
/// may differ from the placement origin of an asymmetric footprint.
pub fn copper_centroid(pads : Array[CopperPad]) -> Point {
  let mut total = 0.0
  let mut x = 0.0
  let mut y = 0.0
  for pad in pads {
    total += pad.area
    x += pad.center.x * pad.area
    y += pad.center.y * pad.area
  }
  if total == 0.0 {
    return { x: 0.0, y: 0.0, }
  }
  { x: x / total, y: y / total, }
}

///|
fn gerber_object_bounds(kind : GerberKind) -> GerberBounds? {
  match kind {
    Flash(shape, center) => Some(bounds_at(center, shape.bounding_radius()))
    Draw(shape, start, end) => {
      let radius = shape.bounding_radius()
      Some(bounds_at(start, radius).union(bounds_at(end, radius)))
    }
    Approximate(bounds) => Some(bounds)
    Arc(arc) => Some(arc.bounds())
    Region(points) => {
      guard points.get(0) is Some(first) else { return None }
      let mut bounds = bounds_at(first, 0.0)
      for point in points {
        bounds = bounds.union(bounds_at(point, 0.0))
      }
      Some(bounds)
    }
  }
}

///|
fn in_flash_hole(kind : GerberKind, point : Point, margin : Double) -> Bool {
  guard kind is Flash(shape, center) &&
    shape.transparent_hole(center) is Some((hole, radius)) else {
    return false
  }
  @math.hypot(point.x - hole.x, point.y - hole.y) + margin < radius
}

///|
fn clear_may_cover(kind : GerberKind, point : Point, margin : Double) -> Bool {
  match kind {
    Arc(arc) => arc.may_cover(point, margin)
    _ => !in_flash_hole(kind, point, margin)
  }
}

///|
/// Only a clear object painted after a flash can invalidate that flash.
/// Bounds can rule out an overlap without claiming to compute clipped area.
fn refs_with_possible_clearance(document : GerberDocument) -> Map[String, Bool] {
  let affected : Map[String, Bool] = Map([])
  let later_clear : Array[(GerberKind, GerberBounds)] = []
  let count = document.features.length()
  for i in 0..<count {
    let feature = document.features[count - i - 1]
    if !feature.dark {
      if gerber_object_bounds(feature.kind) is Some(bounds) {
        later_clear.push((feature.kind, bounds))
      }
    } else if !later_clear.is_empty() &&
      feature.kind is Flash(shape, center) &&
      feature.refdes is Some(refdes) {
      let radius = shape.bounding_radius()
      let pad_bounds = bounds_at(center, radius)
      if later_clear.any(item => {
          item.1.overlaps(pad_bounds) && clear_may_cover(item.0, center, radius)
        }) {
        affected[designator(refdes)] = true
      }
    }
  }
  affected
}

///|
/// Approximate nearby copper from flashes, arc strokes and regions. This cannot establish
/// ownership. A possibly intersecting clear object removes positive evidence.
pub fn copper_at(
  document : GerberDocument,
  point : Point,
  tolerance : Double,
) -> Bool {
  let mut covered = false
  let search = bounds_at(point, tolerance)
  for feature in document.features {
    if !feature.dark {
      if gerber_object_bounds(feature.kind) is Some(bounds) &&
        bounds.overlaps(search) &&
        clear_may_cover(feature.kind, point, tolerance) {
        covered = false
      }
      continue
    }
    let contains = match feature.kind {
      Flash(shape, center) => shape.expanded(tolerance).contains(center, point)
      Region(points) => polygon_contains(points, point)
      Arc(arc) => arc.covers(point, tolerance)
      _ => false
    }
    if contains {
      covered = true
    }
  }
  covered
}

///|
priv enum PadEvidence {
  ByReference(Int32, Point, Double)
  CopperOnly
  Unverified
  PossibleClearance
}

///|
fn pad_evidence(
  document : GerberDocument,
  refdes : Array[String],
  positions : Array[Point],
  tolerance_mm : Double,
) -> Array[PadEvidence] {
  let count = positions.length().min(refdes.length())
  let groups = pad_groups(gerber_pads(document))
  let affected = refs_with_possible_clearance(document)
  let evidence = []
  for i in 0..<count {
    let point = positions[i]
    let reference = designator(refdes[i])
    if affected.contains(reference) {
      evidence.push(PossibleClearance)
      continue
    }
    evidence.push(
      match groups.get(reference) {
        Some(group) if group.any(pad => pad.area > 0.0) => {
          let delta = difference(point, copper_centroid(group))
          ByReference(group.length(), delta, magnitude(delta))
        }
        _ =>
          if copper_at(document, point, tolerance_mm) {
            CopperOnly
          } else {
            Unverified
          }
      },
    )
  }
  evidence
}

///|
fn pad_finding(
  refdes : String,
  evidence : PadEvidence,
  tolerance : Double,
) -> Json? {
  match evidence {
    ByReference(_, delta, distance) if distance > tolerance =>
      Some({
        "ref": Json(refdes),
        "kind": Json("pad_offset"),
        "delta_x_mm": Json(delta.x),
        "delta_y_mm": Json(delta.y),
        "distance_mm": Json(distance),
      })
    _ => None
  }
}

///|
/// Return attributable pad-centre offsets beyond tolerance. The audit report
/// also exposes the evidence for coordinates whose ownership is unknown.
pub fn check_pads(
  document : GerberDocument,
  refdes : Array[String],
  positions : Array[Point],
  tolerance_mm : Double,
) -> Array[Json] {
  let items = pad_evidence(document, refdes, positions, tolerance_mm)
  let findings = []
  for i in 0..<items.length() {
    if pad_finding(refdes[i], items[i], tolerance_mm) is Some(item) {
      findings.push(item)
    }
  }
  findings
}
