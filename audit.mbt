///|
/// Schema used by audit results and CLI input errors.
pub const REPORT_SCHEMA_VERSION : Int32 = 3

///|
pub(all) enum Verdict {
  Pass
  Different
  Indeterminate
}

///|
pub struct AuditResult {
  verdict : Verdict
  report : Json
}

///|
fn verdict_name(verdict : Verdict) -> String {
  match verdict {
    Pass => "pass"
    Different => "different"
    Indeterminate => "indeterminate"
  }
}

///|
fn side_name(side : Side) -> String {
  match side {
    Top => "top"
    Bottom => "bottom"
  }
}

///|
fn measured_angle(placement : Placement, convention : FileConvention) -> Double {
  let offset = match placement.side {
    Top => convention.top_angle_offset
    Bottom => convention.bottom_angle_offset
  }
  placement.angle_deg * convention.angle_sign + offset
}

///|
fn same_text(a : String, b : String) -> Bool {
  a.trim().to_lower() == b.trim().to_lower()
}

///|
fn findings(
  reference : Placement,
  target : Placement,
  policy : Policy,
  frame : Frame?,
  items : Array[Json],
) -> Unit {
  if reference.side != target.side {
    items.push({
      "ref": Json(reference.refdes),
      "kind": Json("side"),
      "baseline": Json(side_name(reference.side)),
      "delivery": Json(side_name(target.side)),
    })
    return
  }
  if !reference.value.is_empty() &&
    !target.value.is_empty() &&
    !same_text(reference.value, target.value) {
    items.push({
      "ref": Json(reference.refdes),
      "kind": Json("value"),
      "baseline": Json(reference.value),
      "delivery": Json(target.value),
    })
  }
  if !reference.footprint.is_empty() &&
    !target.footprint.is_empty() &&
    !same_text(reference.footprint, target.footprint) {
    items.push({
      "ref": Json(reference.refdes),
      "kind": Json("package"),
      "baseline": Json(reference.footprint),
      "delivery": Json(target.footprint),
    })
  }
  guard frame is Some(frame) else { return }
  let expected = position(
    reference,
    policy.baseline.units,
    policy.baseline.bottom_x is Negated,
  )
  let canonical = position(target, policy.delivery.units, frame.negate_bottom_x)
  let predicted = frame.transform.apply(canonical)
  let delta = difference(predicted, expected)
  let distance = magnitude(delta)
  if distance > policy.position_mm {
    items.push({
      "ref": Json(reference.refdes),
      "kind": Json("position"),
      "delta_x_mm": Json(delta.x),
      "delta_y_mm": Json(delta.y),
      "distance_mm": Json(distance),
    })
  }
  let rotation_deg = frame.rotation_deg
  let angle_delta = angle_wrap(
    measured_angle(target, policy.delivery) +
    rotation_deg -
    measured_angle(reference, policy.baseline),
  )
  if angle_delta.abs() > policy.angle_deg {
    items.push({
      "ref": Json(reference.refdes),
      "kind": Json("angle"),
      "delta_deg": Json(angle_delta),
    })
  }
}

///|
priv struct SideTargets {
  refs : Array[String]
  points : Array[Point]
}

///|
/// Delivery components on one side, already mapped into the baseline frame.
fn side_targets(
  delivery : Map[String, Placement],
  side : Side,
  frame : Frame,
  policy : Policy,
) -> SideTargets {
  let refs : Array[String] = []
  let points : Array[Point] = []
  let keys = delivery.keys().collect()
  keys.sort()
  for key in keys {
    let part = delivery[key]
    if part.side == side {
      let canonical = position(
        part,
        policy.delivery.units,
        frame.negate_bottom_x,
      )
      refs.push(key)
      points.push(frame.transform.apply(canonical))
    }
  }
  { refs, points, }
}

///|
/// Compare two exports of the same board revision.
/// Membership and side are always checked. Geometry requires a unique frame.
///
/// `top_gerber` and `bottom_gerber` are optional parsed copper layers used for
/// the pad-level cross-check; when absent the report records an empty pad list
/// and the previous behaviour is unchanged.
pub fn audit(
  baseline_table : PlacementTable,
  delivery_table : PlacementTable,
  policy : Policy,
  top_gerber~ : GerberDocument? = None,
  bottom_gerber~ : GerberDocument? = None,
) -> AuditResult {
  let baseline = baseline_table.rows
  let delivery = delivery_table.rows
  let anchor_issues : Array[Json] = []
  let pairs : Array[AnchorPair] = []
  for key in policy.anchors {
    match (baseline.get(key), delivery.get(key)) {
      (Some(a), Some(b)) if a.side == b.side =>
        pairs.push({ baseline: a, delivery: b, })
      (Some(_), Some(_)) =>
        anchor_issues.push({ "ref": Json(key), "kind": Json("anchor_side") })
      (None, None) =>
        anchor_issues.push({
          "ref": Json(key),
          "kind": Json("anchor_missing_both"),
        })
      (None, _) =>
        anchor_issues.push({
          "ref": Json(key),
          "kind": Json("anchor_missing_baseline"),
        })
      (_, None) =>
        anchor_issues.push({
          "ref": Json(key),
          "kind": Json("anchor_missing_delivery"),
        })
    }
  }
  let has_bottom = baseline.values().any(part => part.side == Bottom) ||
    delivery.values().any(part => part.side == Bottom)
  let search = if anchor_issues.is_empty() {
    candidate_frames(pairs, policy, has_bottom)
  } else {
    { baseline_has_area: false, accepted: [], rejected: [], }
  }
  let candidates = search.accepted
  let frame = if candidates.length() == 1 { Some(candidates[0]) } else { None }
  let keys = baseline.keys().collect()
  keys.sort()
  let extra = delivery.keys().filter(key => !baseline.contains(key)).collect()
  extra.sort()
  let missing = keys.filter(key => !delivery.contains(key))
  // A missing designator and an extra one at the same expected position is a
  // rename, not two independent errors. Pair them geometrically so the report
  // says "swapped" instead of "missing + extra".
  let swap_for_missing : Map[String, String] = Map([])
  let swapped_extra : Map[String, Bool] = Map([])
  match frame {
    Some(chosen) => {
      let limit = (policy.position_mm * 2.0).max(0.2)
      for key in missing {
        let expected = position(
          baseline[key],
          policy.baseline.units,
          policy.baseline.bottom_x is Negated,
        )
        let mut best = ""
        let mut best_distance = limit
        for candidate in extra {
          if !swapped_extra.contains(candidate) {
            let canonical = position(
              delivery[candidate],
              policy.delivery.units,
              chosen.negate_bottom_x,
            )
            let predicted = chosen.transform.apply(canonical)
            let distance = magnitude(difference(predicted, expected))
            if distance < best_distance {
              best_distance = distance
              best = candidate
            }
          }
        }
        if !best.is_empty() {
          swap_for_missing[key] = best
          swapped_extra[best] = true
        }
      }
    }
    None => ()
  }
  let evidence : Array[Json] = []
  for key in keys {
    match delivery.get(key) {
      Some(target) => findings(baseline[key], target, policy, frame, evidence)
      None =>
        match swap_for_missing.get(key) {
          Some(partner) =>
            evidence.push({
              "ref": Json(key),
              "kind": Json("swapped"),
              "with": Json(partner),
            })
          None => evidence.push({ "ref": Json(key), "kind": Json("missing") })
        }
    }
  }
  for key in extra {
    if !swapped_extra.contains(key) {
      evidence.push({ "ref": Json(key), "kind": Json("extra") })
    }
  }
  let pad_differences : Array[Json] = []
  let pad_results : Array[Json] = []
  let pad_warnings : Array[Json] = []
  let pad_sides : Array[Json] = []
  let panel_cells : Array[Json] = []
  let mut pad_checked = 0
  for layer in [(Top, top_gerber), (Bottom, bottom_gerber)] {
    guard layer is (side, Some(document)) else { continue }
    pad_sides.push(Json(side_name(side)))
    if document.panel_cell is Some(cell) {
      panel_cells.push({
        "side": Json(side_name(side)),
        "row": Json(cell.row),
        "column": Json(cell.column),
        "rows": Json(cell.grid.rows),
        "columns": Json(cell.grid.columns),
        "offset_x_mm": Json(cell.offset_mm.x),
        "offset_y_mm": Json(cell.offset_mm.y),
      })
    }
    for warning in document.warnings {
      pad_warnings.push({
        "side": Json(side_name(side)),
        "message": Json(warning),
      })
    }
    guard frame is Some(chosen) else { continue }
    let targets = side_targets(delivery, side, chosen, policy)
    let items = pad_evidence(
      document,
      targets.refs,
      targets.points,
      policy.pad_mm,
    )
    for i in 0..<items.length() {
      let refdes = targets.refs[i]
      let details : Json = match items[i] {
        ByReference(pad_count, _, distance) => {
          pad_checked += 1
          {
            "status": Json("by_reference"),
            "pad_count": Json(pad_count),
            "distance_mm": Json(distance),
            "within_tolerance": Json(distance <= policy.pad_mm),
          }
        }
        CopperOnly => { "status": Json("copper_only") }
        Unverified => { "status": Json("unverified") }
        PossibleClearance =>
          { "status": Json("unverified"), "reason": Json("possible_clearance") }
        RepeatedReference =>
          { "status": Json("unverified"), "reason": Json("repeated_reference") }
      }
      pad_results.push({
        "ref": Json(refdes),
        "side": Json(side_name(side)),
        "evidence": details,
      })
      if pad_finding(refdes, items[i], policy.pad_mm) is Some(item) {
        pad_differences.push(item)
      }
    }
  }
  let pad_skipped = !pad_sides.is_empty() && frame is None
  let pad_status = if pad_sides.is_empty() {
    "not_requested"
  } else if pad_skipped {
    "skipped"
  } else if pad_checked < pad_results.length() {
    "incomplete"
  } else {
    "complete"
  }
  let (verdict, reason) = if !anchor_issues.is_empty() {
    (Indeterminate, Json("invalid_anchors"))
  } else if !search.baseline_has_area {
    (Indeterminate, Json("degenerate_baseline_anchors"))
  } else if candidates.is_empty() {
    (Indeterminate, Json("no_matching_frame"))
  } else if frame is None {
    (Indeterminate, Json("ambiguous_frame"))
  } else if !evidence.is_empty() || !pad_differences.is_empty() {
    (Different, Json(null))
  } else if pad_status == "incomplete" {
    (Indeterminate, Json("insufficient_pad_evidence"))
  } else if baseline.length() == pairs.length() {
    (Indeterminate, Json("no_independent_components"))
  } else {
    (Pass, Json(null))
  }
  let report : Json = {
    "schema_version": Json(REPORT_SCHEMA_VERSION),
    "status": Json(verdict_name(verdict)),
    "reason": reason,
    "frame": match frame {
      Some(chosen) => frame_json(chosen, policy)
      None => Json(null)
    },
    "candidate_frames": Json(
      candidates.map(candidate => frame_json(candidate, policy)),
    ),
    "rejected_frames": Json(search.rejected),
    "anchors": Json(policy.anchors),
    "anchor_issues": Json(anchor_issues),
    "baseline_count": Json(baseline.length()),
    "delivery_count": Json(delivery.length()),
    "differences": Json(evidence),
    "pad_differences": Json(pad_differences),
    "pad_checked": Json(pad_checked),
    "pad_skipped": Json(pad_skipped),
    "pad_status": Json(pad_status),
    "pad_sides": Json(pad_sides),
    "panel_cells": Json(panel_cells),
    "pad_evidence": Json(pad_results),
    "pad_warnings": Json(pad_warnings),
    "tolerances": {
      "position_mm": Json(policy.position_mm),
      "angle_deg": Json(policy.angle_deg),
      "anchor_mm": Json(policy.anchor_mm),
      "pad_mm": Json(policy.pad_mm),
    },
  }
  { verdict, report, }
}
