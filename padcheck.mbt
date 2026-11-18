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
/// Approximate nearby copper from flashes and regions. This cannot establish
/// which component owns the copper, and does not account for drawn traces.
pub fn copper_at(
  document : GerberDocument,
  point : Point,
  tolerance : Double,
) -> Bool {
  let mut covered = false
  for feature in document.features {
    let contains = match feature.kind {
      Flash(shape, center) =>
        if feature.dark {
          shape.expanded(tolerance).contains(center, point)
        } else {
          shape.contains(center, point)
        }
      Region(points) => polygon_contains(points, point)
      _ => false
    }
    if contains {
      covered = feature.dark
    }
  }
  covered
}

///|
priv enum PadEvidence {
  ByReference(Int32, Point, Double)
  CopperOnly
  Unverified
}

///|
fn pad_evidence(
  document : GerberDocument,
  refdes : Array[String],
  positions : Array[Point],
  tolerance_mm : Double,
) -> Array[PadEvidence] {
  let count = positions.length().min(refdes.length())
  if !document.warnings.is_empty() {
    return Array::make(count, Unverified)
  }
  let groups = pad_groups(gerber_pads(document))
  let evidence = []
  for i in 0..<count {
    let point = positions[i]
    evidence.push(
      match groups.get(designator(refdes[i])) {
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
