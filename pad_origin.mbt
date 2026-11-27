///|
priv enum PadOriginRule {
  Offset(Side, Double, Point, String)
  Review(String)
}

///|
priv struct PadOrigins {
  refs : Map[String, PadOriginRule]
  footprints : Map[String, PadOriginRule]
}

///|
fn read_pad_origins(document : Json) -> PadOrigins raise InputError {
  let refs : Map[String, PadOriginRule] = Map([])
  let footprints : Map[String, PadOriginRule] = Map([])
  guard json_get(document, "pad_origins") is Some(raw) else {
    return { refs, footprints, }
  }
  guard raw is Array(rules) else {
    raise InvalidInput("pad_origins", "使用规则数组")
  }
  for index, rule in rules {
    let field = "pad_origins[\{index}]"
    policy_fields(rule, field, [
      "ref", "footprint", "mode", "source", "side", "angle_deg", "dx_mm", "dy_mm",
    ])
    |> ignore
    let (key, rules) = match
      (json_get(rule, "ref"), json_get(rule, "footprint")) {
      (Some(String(refdes)), None) => (designator(refdes), refs)
      (None, Some(String(footprint))) =>
        (footprint.trim().to_owned().to_lower(), footprints)
      _ => raise InvalidInput(field, "只填写 ref 或 footprint 之一")
    }
    if key.is_empty() || rules.contains(key) {
      raise InvalidInput(field, "规则目标为空或重复")
    }
    let source = json_string(rule, "source").trim().to_owned()
    if source.is_empty() {
      raise InvalidInput(
        field + ".source",
        "请填写设计依据或人工复查原因",
      )
    }
    let side = json_get(rule, "side")
    let angle = json_get(rule, "angle_deg")
    let x = json_get(rule, "dx_mm")
    let y = json_get(rule, "dy_mm")
    let parsed = match (json_string(rule, "mode"), side, angle, x, y) {
      ("review", None, None, None, None) => Review(source)
      (
        "offset",
        Some(String(side)),
        Some(Number(angle, ..)),
        Some(Number(x, ..)),
        Some(Number(y, ..)),
      ) if angle.abs() <= 360.0 && x.abs() <= 1000.0 && y.abs() <= 1000.0 => {
        let side = match side {
          "top" => Top
          "bottom" => Bottom
          _ => raise InvalidInput(field + ".side", "使用 top 或 bottom")
        }
        Offset(side, angle, { x, y, }, source)
      }
      ("offset", _, _, _, _) =>
        raise InvalidInput(
          field, "校正需填写板面、±360° 内的角度和 ±1000 mm 内的 DX、DY",
        )
      ("review", _, _, _, _) =>
        raise InvalidInput(
          field, "人工复查规则无需提供板面、角度或偏移",
        )
      _ => raise InvalidInput(field + ".mode", "使用 offset 或 review")
    }
    rules[key] = parsed
  }
  { refs, footprints, }
}

///|
/// Corrections are measured from the origin to the centroid in baseline board
/// axes. A baseline pose mismatch requires review instead of rotating a guess.
fn apply_pad_origin(
  evidence : PadEvidence,
  refdes : String,
  side : Side,
  baseline : Placement?,
  policy : Policy,
) -> (PadEvidence, Json?) {
  guard evidence is ByReference(count, raw, distance) && baseline is Some(part) else {
    return (evidence, None)
  }
  let (rule, matched_by) = match policy.pad_origins.refs.get(refdes) {
    Some(rule) => (rule, "ref")
    None =>
      match
        policy.pad_origins.footprints.get(
          part.footprint.trim().to_owned().to_lower(),
        ) {
        Some(rule) => (rule, "footprint")
        None => return (evidence, None)
      }
  }
  let (result, status, source, offset) = match rule {
    Review(source) => (Unverified, "review", source, None)
    Offset(expected_side, angle, offset, source) =>
      if side == part.side &&
        side == expected_side &&
        angle_wrap(measured_angle(part, policy.baseline) - angle).abs() <=
        0.000001 {
        let corrected = { x: raw.x + offset.x, y: raw.y + offset.y, }
        (
          ByReference(count, corrected, magnitude(corrected)),
          "corrected",
          source,
          Some(offset),
        )
      } else {
        (Unverified, "pose_mismatch", source, None)
      }
  }
  let origin : Map[String, Json] = {
    "status": Json(status),
    "matched_by": Json(matched_by),
    "source": Json(source),
    "raw_distance_mm": Json(distance),
    "raw_delta_x_mm": Json(raw.x),
    "raw_delta_y_mm": Json(raw.y),
  }
  if offset is Some(vector) {
    origin["applied_dx_mm"] = Json(vector.x)
    origin["applied_dy_mm"] = Json(vector.y)
  }
  (result, Some(Json::object(origin)))
}
