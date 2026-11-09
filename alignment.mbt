///|
priv struct AnchorPair {
  baseline : Placement
  delivery : Placement
}

///|
priv struct Frame {
  quarter_turns : Int32
  negate_bottom_x : Bool
  translation : Point
  max_anchor_error_mm : Double
}

///|
fn unit_scale(unit : Units) -> Double {
  match unit {
    Millimetres => 1.0
    Inches => 25.4
    Mils => 0.0254
  }
}

///|
fn position(
  placement : Placement,
  unit : Units,
  negate_bottom_x : Bool,
) -> Point {
  let scale = unit_scale(unit)
  let x_sign = if negate_bottom_x && placement.side == Bottom {
    -1.0
  } else {
    1.0
  }
  { x: placement.xy.x * scale * x_sign, y: placement.xy.y * scale, }
}

///|
fn rotation(xy : Point, turns : Int32) -> Point {
  match turns {
    1 => { x: -xy.y, y: xy.x, }
    2 => { x: -xy.x, y: -xy.y, }
    3 => { x: xy.y, y: -xy.x, }
    _ => xy
  }
}

///|
fn difference(a : Point, b : Point) -> Point {
  { x: a.x - b.x, y: a.y - b.y, }
}

///|
fn magnitude(a : Point) -> Double {
  (a.x * a.x + a.y * a.y).sqrt()
}

///|
fn has_area(points : Array[Point], minimum_span : Double) -> Bool {
  let mut origin = points[0]
  let mut farthest = points[0]
  let mut distance = minimum_span
  for i, first in points {
    for j in (i + 1)..<points.length() {
      let span = magnitude(difference(points[j], first))
      if span > distance {
        distance = span
        origin = first
        farthest = points[j]
      }
    }
  }
  if distance <= minimum_span {
    return false
  }
  let axis = difference(farthest, origin)
  for point in points {
    let offset = difference(point, origin)
    let altitude = (axis.x * offset.y - axis.y * offset.x).abs() / distance
    if altitude > minimum_span {
      return true
    }
  }
  false
}

///|
fn fit_frame(
  baseline : Array[Point],
  delivery : Array[Point],
  turns : Int32,
  negate_bottom_x : Bool,
) -> Frame {
  let mut sum_x = 0.0
  let mut sum_y = 0.0
  let offsets : Array[Point] = []
  for i, point in delivery {
    let offset = difference(baseline[i], rotation(point, turns))
    offsets.push(offset)
    sum_x += offset.x
    sum_y += offset.y
  }
  let count = offsets.length().to_double()
  let translation = { x: sum_x / count, y: sum_y / count, }
  let mut max_anchor_error_mm = 0.0
  for offset in offsets {
    let error = magnitude(difference(offset, translation))
    if error > max_anchor_error_mm {
      max_anchor_error_mm = error
    }
  }
  { quarter_turns: turns, negate_bottom_x, translation, max_anchor_error_mm, }
}

///|
fn frame_json(frame : Frame) -> Json {
  {
    "rotation_deg": Json(frame.quarter_turns * 90),
    "delivery_bottom_x": Json(
      if frame.negate_bottom_x {
        "negated"
      } else {
        "direct"
      },
    ),
    "delivery_to_baseline_mm": {
      "x": Json(frame.translation.x),
      "y": Json(frame.translation.y),
    },
    "max_anchor_error_mm": Json(frame.max_anchor_error_mm),
  }
}

///|
priv struct FrameSearch {
  baseline_has_area : Bool
  accepted : Array[Frame]
  rejected : Array[Json]
}

///|
fn candidate_frames(
  pairs : Array[AnchorPair],
  policy : Policy,
  has_bottom : Bool,
) -> FrameSearch {
  let baseline = pairs.map(pair => {
    position(
      pair.baseline,
      policy.baseline.units,
      policy.baseline.bottom_x is Negated,
    )
  })
  let min_span = 2.0 * policy.anchor_mm
  let baseline_has_area = has_area(baseline, min_span)
  let accepted : Array[Frame] = []
  let rejected : Array[Json] = []
  if !baseline_has_area {
    return { baseline_has_area, accepted, rejected, }
  }
  let mirror_options = match policy.delivery.bottom_x {
    Direct => [false]
    Negated => [true]
    Auto => if has_bottom { [false, true] } else { [false] }
  }
  for mirror in mirror_options {
    let delivery = pairs.map(pair => {
      position(pair.delivery, policy.delivery.units, mirror)
    })
    if !has_area(delivery, min_span) {
      rejected.push({
        "delivery_bottom_x": Json(if mirror { "negated" } else { "direct" }),
        "reason": Json("degenerate_delivery_anchors"),
      })
      continue
    }
    for turns in policy.rotations {
      let frame = fit_frame(baseline, delivery, turns, mirror)
      if frame.max_anchor_error_mm <= policy.anchor_mm {
        accepted.push(frame)
      } else {
        rejected.push({
          "frame": frame_json(frame),
          "reason": Json("anchor_tolerance_exceeded"),
        })
      }
    }
  }
  { baseline_has_area, accepted, rejected, }
}
