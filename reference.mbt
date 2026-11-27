///|
fn bounded_reference_text(value : String) -> String {
  if value.length() > 160 {
    value.clamped_view(end=160).to_owned() + "…"
  } else {
    value
  }
}

///|
/// Look up one normalized designator in a completed audit. The lookup includes
/// findings outside the online preview and respects the audit's assembly scope.
pub fn lookup_reference(
  report : Json,
  baseline : PlacementTable,
  delivery : PlacementTable,
  policy : Policy,
  reference : String,
) -> Json {
  let key = designator(reference)
  let label = bounded_reference_text(key)
  let scope = match policy.placement_import {
    Some(settings) => settings.scope
    None => All
  }
  let expected = scope is Expected(refs) && refs.contains(key)
  let base = baseline.rows.get(key)
  let target = delivery.rows.get(key)
  if key.is_empty() ||
    !scope.includes(key) ||
    !(expected || base is Some(_) || target is Some(_)) {
    return { "ref": Json(label), "found": Json(false) }
  }
  let differences : Array[Json] = []
  for item in json_array(report, "differences") {
    let primary = json_string(item, "ref")
    let partner = json_string(item, "with")
    if primary == key || partner == key {
      let fields : Map[String, Json] = {
        "kind": Json(json_string(item, "kind")),
      }
      for name in ["baseline", "delivery"] {
        if json_get(item, name) is Some(String(value)) {
          fields[name] = Json(bounded_reference_text(value))
        }
      }
      if !partner.is_empty() {
        fields["with"] = Json(
          bounded_reference_text(if primary == key { partner } else { primary }),
        )
      }
      for name in ["distance_mm", "delta_deg"] {
        if json_get(item, name) is Some(value) {
          fields[name] = value
        }
      }
      differences.push(Json::object(fields))
    }
  }
  let copper : Map[String, Json] = { "status": Json("unavailable") }
  for item in json_array(report, "pad_evidence") {
    if json_string(item, "ref") != key {
      continue
    }
    if json_get(item, "evidence") is Some(evidence) {
      for name in ["status", "reason", "distance_mm", "within_tolerance"] {
        if json_get(evidence, name) is Some(value) {
          copper[name] = value
        }
      }
      if json_get(evidence, "origin") is Some(origin) {
        copper["origin_status"] = Json(json_string(origin, "status"))
        copper["source"] = Json(
          bounded_reference_text(json_string(origin, "source")),
        )
      }
    }
    break
  }
  let baseline_side = match base {
    Some(part) => side_name(part.side)
    None => ""
  }
  let delivery_side = match target {
    Some(part) => side_name(part.side)
    None => ""
  }
  let panel_side = if delivery_side.is_empty() {
    baseline_side
  } else {
    delivery_side
  }
  {
    "ref": Json(label),
    "found": Json(true),
    "baseline_side": Json(baseline_side),
    "delivery_side": Json(delivery_side),
    "differences": Json(differences),
    "copper": Json::object(copper),
    "panels": Json(
      json_array(report, "panel_cells").filter(cell => {
        json_string(cell, "side") == panel_side
      }),
    ),
  }
}
