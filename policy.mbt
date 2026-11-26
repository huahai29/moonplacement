///|
priv enum Units {
  Millimetres
  Inches
  Mils
}

///|
priv enum BottomX {
  Direct
  Negated
  Auto
}

///|
/// How the anchor set is turned into a delivery-to-baseline frame.
///
/// `Enumerate` keeps the original quarter-turn search. `Register` hands the
/// anchors to the registration engine and estimates a continuous transform.
priv enum AlignmentMode {
  Enumerate
  Register(TransformModel)
}

///|
priv struct FileConvention {
  units : Units
  bottom_x : BottomX
  angle_sign : Double
  top_angle_offset : Double
  bottom_angle_offset : Double
}

///|
pub struct Policy {
  priv baseline : FileConvention
  priv delivery : FileConvention
  priv anchors : Array[String]
  priv rotations : Array[Int32]
  priv alignment : AlignmentMode
  priv position_mm : Double
  priv angle_deg : Double
  priv anchor_mm : Double
  priv pad_mm : Double
  priv placement_import : PlacementImport?
}

///|
priv struct FileJson {
  unit : String
  bottom_x : String
  angle_sign : Int32
  top_angle_offset_deg : Double
  bottom_angle_offset_deg : Double
} derive(FromJson)

///|
priv struct PolicyJson {
  baseline : FileJson
  delivery : FileJson
  anchors : Array[String]
  rotation : String
  position_tolerance_mm : Double
  angle_tolerance_deg : Double
  anchor_tolerance_mm : Double
} derive(FromJson)

///|
fn read_convention(
  raw : FileJson,
  field : String,
  allow_auto : Bool,
) -> FileConvention raise InputError {
  let units = match raw.unit {
    "mm" => Millimetres
    "in" => Inches
    "mil" => Mils
    _ => raise InvalidInput("\{field}.unit", "使用 mm、in 或 mil")
  }
  let bottom_x = match raw.bottom_x {
    "direct" => Direct
    "negated" => Negated
    "auto" if allow_auto => Auto
    _ =>
      raise InvalidInput(
        "\{field}.bottom_x",
        "基准表使用 direct 或 negated；送厂表也可使用 auto",
      )
  }
  if raw.angle_sign != 1 && raw.angle_sign != -1 {
    raise InvalidInput("\{field}.angle_sign", "使用 1 或 -1")
  }
  let top_angle_offset = raw.top_angle_offset_deg
  let bottom_angle_offset = raw.bottom_angle_offset_deg
  for offset in [top_angle_offset, bottom_angle_offset] {
    if offset.is_nan() || offset.abs() > 360.0 {
      raise InvalidInput(field, "角度零位偏移应在 ±360° 以内")
    }
  }
  {
    units,
    bottom_x,
    angle_sign: raw.angle_sign.to_double(),
    top_angle_offset,
    bottom_angle_offset,
  }
}

///|
fn tolerance(
  value : Double,
  maximum : Double,
  field : String,
) -> Double raise InputError {
  if value.is_nan() || value <= 0.0 || value > maximum {
    raise InvalidInput(field, "容差必须大于 0 且不超过 \{maximum}")
  }
  value
}

///|
/// Read the optional `alignment` selector. The field is absent in every shipped
/// configuration, so `enumerate` stays the backwards-compatible default.
fn read_alignment(document : Json) -> AlignmentMode raise InputError {
  let field = match document {
    Object(fields) => fields.get("alignment")
    _ => None
  }
  match field {
    None => Enumerate
    Some(value) =>
      match value {
        String(text) =>
          match text {
            "enumerate" | "quarter" => Enumerate
            "rigid" => Register(Rigid)
            "similarity" => Register(Similarity)
            "affine" => Register(Affine)
            _ =>
              raise InvalidInput(
                "alignment", "使用 enumerate、rigid、similarity 或 affine",
              )
          }
        _ => raise InvalidInput("alignment", "alignment 必须是字符串")
      }
  }
}

///|
/// Read an optional numeric tolerance from the raw policy document.
fn read_optional_tolerance(
  document : Json,
  key : String,
  fallback : Double,
) -> Double raise InputError {
  let field = match document {
    Object(fields) => fields.get(key)
    _ => None
  }
  match field {
    None => fallback
    Some(value) =>
      match value {
        Number(number, ..) => tolerance(number, 100.0, key)
        _ => raise InvalidInput(key, "必须是数字")
      }
  }
}

///|
/// Parse the coordinate conventions and tolerances for a comparison.
pub fn read_policy(input : String) -> Policy raise InputError {
  if input.length() > 65_536 {
    raise InvalidInput("policy", "配置文件超过 65536 字符单元")
  }
  let document = @json.parse(input) catch {
    error => raise InvalidInput("policy", "配置无法解析：\{error}")
  }
  let raw : PolicyJson = @json.from_json(document) catch {
    error => raise InvalidInput("policy", "配置无法解析：\{error}")
  }
  let baseline = read_convention(raw.baseline, "baseline", false)
  let delivery = read_convention(raw.delivery, "delivery", true)
  if raw.anchors.length() < 3 || raw.anchors.length() > 64 {
    raise InvalidInput("anchors", "需要 3～64 个可信位号")
  }
  let anchors : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for entry in raw.anchors {
    let key = designator(entry)
    if key.is_empty() || seen.contains(key) {
      raise InvalidInput("anchors", "位号为空或重复：\{entry}")
    }
    seen[key] = true
    anchors.push(key)
  }
  let rotations = match raw.rotation {
    "0" => [0]
    "90" => [1]
    "180" => [2]
    "270" => [3]
    "auto" => [0, 1, 2, 3]
    _ => raise InvalidInput("rotation", "使用 0、90、180、270 或 auto")
  }
  let alignment = read_alignment(document)
  let pad_mm = read_optional_tolerance(document, "pad_tolerance_mm", 0.1)
  {
    baseline,
    delivery,
    anchors,
    rotations,
    alignment,
    position_mm: tolerance(
      raw.position_tolerance_mm,
      100.0,
      "position_tolerance_mm",
    ),
    angle_deg: tolerance(raw.angle_tolerance_deg, 180.0, "angle_tolerance_deg"),
    anchor_mm: tolerance(raw.anchor_tolerance_mm, 100.0, "anchor_tolerance_mm"),
    pad_mm,
    placement_import: read_placement_import(document, anchors),
  }
}
