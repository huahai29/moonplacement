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
/// Group pads by their X2 component reference. Pads without an attribution are
/// dropped; the caller falls back to a coverage test in that case.
pub fn pad_groups(pads : Array[CopperPad]) -> Map[String, Array[CopperPad]] {
  let groups : Map[String, Array[CopperPad]] = Map([])
  for pad in pads {
    match pad.refdes {
      Some(key) =>
        match groups.get(key) {
          Some(group) => group.push(pad)
          None => groups[key] = [pad]
        }
      None => ()
    }
  }
  groups
}

///|
/// Area-weighted centre of a pad group. Solder paste and copper mass are
/// dominated by the larger pads, which is the centre a placement coordinate
/// should point at.
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
/// True when any dark flash or region covers `point`, allowing `tolerance` mm of
/// slack around the pad outline.
pub fn copper_at(
  document : GerberDocument,
  point : Point,
  tolerance : Double,
) -> Bool {
  for feature in document.features {
    if feature.dark {
      match feature.kind {
        Flash(shape, center) =>
          if shape.expanded(tolerance).contains(center, point) {
            return true
          }
        Region(points) => if polygon_contains(points, point) { return true }
        _ => ()
      }
    }
  }
  false
}

///|
/// Cross-check expected component positions against a Gerber layer.
///
/// When the layer carries X2 component attributes the check compares the
/// area-weighted copper centroid of each component with its exported position,
/// which catches a coordinate that sits on the wrong pad. Without X2 the check
/// falls back to "is there dark copper at this point at all".
pub fn check_pads(
  document : GerberDocument,
  refdes : Array[String],
  positions : Array[Point],
  tolerance_mm : Double,
) -> Array[Json] {
  let pads = gerber_pads(document)
  let groups = pad_groups(pads)
  let attributed = !groups.is_empty()
  let findings : Array[Json] = []
  let count = positions.length().min(refdes.length())
  for i in 0..<count {
    let key = refdes[i]
    let point = positions[i]
    if attributed {
      match groups.get(key) {
        Some(group) => {
          let centroid = copper_centroid(group)
          let delta = difference(point, centroid)
          let distance = magnitude(delta)
          if distance > tolerance_mm {
            findings.push({
              "ref": Json(key),
              "kind": Json("pad_offset"),
              "delta_x_mm": Json(delta.x),
              "delta_y_mm": Json(delta.y),
              "distance_mm": Json(distance),
            })
          }
        }
        None => ()
      }
    } else if !copper_at(document, point, tolerance_mm) {
      findings.push({ "ref": Json(key), "kind": Json("no_copper") })
    }
  }
  findings
}
