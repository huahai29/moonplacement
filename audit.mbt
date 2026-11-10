///|
/// Schema used by audit results and CLI input errors.
pub const REPORT_SCHEMA_VERSION : Int32 = 2

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
  guard frame is Some(frame) else { return }
  let expected = position(
    reference,
    policy.baseline.units,
    policy.baseline.bottom_x is Negated,
  )
  let canonical = position(target, policy.delivery.units, frame.negate_bottom_x)
  let rotated = rotation(canonical, frame.quarter_turns)
  let delta = difference(frame.translation, difference(expected, rotated))
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
  let rotation_deg = (frame.quarter_turns * 90).to_double()
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
/// Compare two exports of the same board revision.
/// Membership and side are always checked. Geometry requires a unique frame.
pub fn audit(
  baseline_table : PlacementTable,
  delivery_table : PlacementTable,
  policy : Policy,
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
  let evidence : Array[Json] = []
  let keys = baseline.keys().collect()
  keys.sort()
  for key in keys {
    match delivery.get(key) {
      Some(target) => findings(baseline[key], target, policy, frame, evidence)
      None => evidence.push({ "ref": Json(key), "kind": Json("missing") })
    }
  }
  let extra = delivery.keys().filter(key => !baseline.contains(key)).collect()
  extra.sort()
  for key in extra {
    evidence.push({ "ref": Json(key), "kind": Json("extra") })
  }
  let (verdict, reason) = if !anchor_issues.is_empty() {
    (Indeterminate, Json("invalid_anchors"))
  } else if !search.baseline_has_area {
    (Indeterminate, Json("degenerate_baseline_anchors"))
  } else if candidates.is_empty() {
    (Indeterminate, Json("no_matching_frame"))
  } else if frame is None {
    (Indeterminate, Json("ambiguous_frame"))
  } else if !evidence.is_empty() {
    (Different, Json(null))
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
    "tolerances": {
      "position_mm": Json(policy.position_mm),
      "angle_deg": Json(policy.angle_deg),
      "anchor_mm": Json(policy.anchor_mm),
    },
  }
  { verdict, report, }
}
