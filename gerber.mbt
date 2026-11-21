///|
/// Raised when a Gerber file cannot be interpreted.
pub(all) suberror GerberError {
  InvalidGerber(String, String)
}

///|
/// One parsed Gerber drawing operation.
pub enum GerberKind {
  /// A flashed aperture and its geometric center, after aperture transforms.
  Flash(Shape, Point)
  /// A stroked segment (`D01`) with the current aperture as its width.
  Draw(Shape, Point, Point)
  /// A directed circular stroke outside a region.
  Arc(GerberArc)
  /// A filled region built from `G36`/`G37`.
  Region(GerberRegion)
}

///|
/// A single feature with the X2 component attribution (if present) and the
/// polarity active when it was drawn.
pub struct GerberFeature {
  kind : GerberKind
  dark : Bool
  refdes : String?
  pin : String?
  statement_number : Int32
  block_instance : Int32?
}

///|
/// Parsed Gerber layer. `warnings` records constructs that were intentionally
/// approximated or skipped so callers can surface them.
pub struct GerberDocument {
  features : Array[GerberFeature]
  warnings : Array[String]
  /// Normalized references that appear in multiple panel copies.
  repeated_refs : Map[String, Bool]
  panel_grids : Array[GerberGrid]
  panel_cell : PanelCell?
}

///|
priv struct GerberWord {
  letter : Char
  value : String
}

///|
priv struct CoordinateFormat {
  digits : Int32
  decimals : Int32
  trailing_zeros_omitted : Bool
}

///|
priv struct GerberState {
  mut format : CoordinateFormat?
  mut scale : Double?
  apertures : Map[Int32, Aperture]
  macros : Map[String, Array[String]]
  mut current_aperture : Int32
  mut mirror_x : Bool
  mut mirror_y : Bool
  mut aperture_angle : Double
  mut aperture_scale : Double
  mut dark : Bool
  mut current : Point?
  mut interpolation : Int32
  mut quadrant_mode : Int32
  mut region : Bool
  mut region_points : Array[Point]
  mut region_error : Double
  mut region_contours : Array[GerberContour]
  mut region_vertices : Int32
  mut refdes : String?
  mut pin_refdes : String?
  mut pin_name : String?
  mut statement_number : Int32
  features : Array[GerberFeature]
  warnings : Array[String]
  mut repeat : GerberRepeat?
  mut repeat_budget : Int32
  keep_panel_base : Bool
  mut panel_base : (Int32, Int32)?
  panel_grids : Array[GerberGrid]
  blocks : Map[Int32, Array[GerberFeature]]
  block_stack : Array[GerberBlock]
  mut block_budget : Int32
  block_seen_refs : Map[String, Bool]
  mut block_instances : Int32
  repeated_refs : Map[String, Bool]
}

///|
fn to_chars(text : String) -> Array[Char] {
  let chars : Array[Char] = []
  for _, ch in text.iter2() {
    chars.push(ch)
  }
  chars
}

///|
fn chars_to_string(chars : Array[Char], start : Int32) -> String {
  let builder = StringBuilder()
  let mut index = start
  while index < chars.length() {
    builder.write_char(chars[index])
    index += 1
  }
  builder.to_string()
}

///|
fn split_statements(
  text : String,
  source : String,
) -> Array[String] raise GerberError {
  let statements : Array[String] = []
  let mut buffer = StringBuilder()
  let mut macro_body = false
  for _, ch in text.iter2() {
    match ch {
      '*' if macro_body => buffer.write_char('*')
      '*' => {
        let statement = buffer.to_string()
        if statement.has_prefix("AM") {
          macro_body = true
          buffer.write_char('*')
        } else if !statement.is_empty() {
          statements.push(statement)
          buffer = StringBuilder()
          if statement == "M02" {
            return statements
          }
        }
      }
      '%' if macro_body => {
        statements.push(buffer.to_string())
        buffer = StringBuilder()
        macro_body = false
      }
      '%' | '\r' | '\n' | '\t' | ' ' => ()
      _ => buffer.write_char(ch)
    }
  }
  if macro_body {
    raise InvalidGerber(source, "光圈宏缺少结束符 %")
  }
  let tail = buffer.to_string()
  if !tail.is_empty() {
    statements.push(tail)
  }
  statements
}

///|
fn parse_code(word : GerberWord, source : String) -> Int32 raise GerberError {
  let mut code = 0
  let mut digits = 0
  for _, ch in word.value.iter2() {
    if !is_digit(ch) || digits >= 6 {
      raise InvalidGerber(
        source,
        "无效的指令编号：\{word.letter}\{word.value}",
      )
    }
    code = code * 10 + digit_value(ch)
    digits += 1
  }
  if digits == 0 {
    raise InvalidGerber(source, "指令缺少编号：\{word.letter}")
  }
  code
}

///|
fn pow10(exponent : Int32) -> Double {
  let mut value = 1.0
  for _ in 0..<exponent {
    value *= 10.0
  }
  value
}

///|
fn parse_format(
  state : GerberState,
  chars : Array[Char],
  source : String,
) -> Unit raise GerberError {
  guard chars
    is [
      'F',
      'S',
      zero_mode,
      notation,
      'X',
      whole,
      fractional,
      'Y',
      y_whole,
      y_fractional,
    ] else {
    raise InvalidGerber(source, "无效的 FS 坐标格式")
  }
  if notation == 'I' {
    raise InvalidGerber(
      source, "不支持增量坐标，请重新导出为绝对坐标",
    )
  }
  if notation != 'A' ||
    (zero_mode != 'L' && zero_mode != 'T') ||
    !is_digit(whole) ||
    !is_digit(fractional) ||
    whole != y_whole ||
    fractional != y_fractional {
    raise InvalidGerber(
      source, "FS 需要使用相同的 X/Y 位宽和绝对坐标",
    )
  }
  let decimals = digit_value(fractional)
  let digits = digit_value(whole) + decimals
  if digits < 1 || digits > 15 {
    raise InvalidGerber(source, "FS 坐标总位宽必须为 1～15")
  }
  state.format = Some({
    digits,
    decimals,
    trailing_zeros_omitted: zero_mode == 'T',
  })
}

///|
fn parse_units(
  state : GerberState,
  statement : String,
  source : String,
) -> Unit raise GerberError {
  state.scale = match statement {
    "MOMM" => Some(1.0)
    "MOIN" => Some(25.4)
    _ => raise InvalidGerber(source, "MO 单位必须为 MM 或 IN")
  }
}

///|
fn parse_aperture(
  state : GerberState,
  chars : Array[Char],
  source : String,
) -> Unit raise GerberError {
  let mut index = 2
  if index < chars.length() && chars[index] == 'D' {
    index += 1
  }
  let mut code = 0
  while index < chars.length() && is_digit(chars[index]) {
    code = code * 10 + digit_value(chars[index])
    index += 1
  }
  if index >= chars.length() {
    raise InvalidGerber(source, "光圈定义缺少模板")
  }
  if state.blocks.contains(code) ||
    state.block_stack.any(block => block.code == code) {
    raise InvalidGerber(source, "光圈编号已用于 AB：D\{code}")
  }
  guard state.scale is Some(scale) else {
    raise InvalidGerber(source, "光圈定义前缺少 MO 单位声明")
  }
  let (template, fields) = match
    aperture_fields(chars_to_string(chars, index), ',') {
    [name] => (name, [])
    [name, values] => (name, aperture_fields(values, 'X'))
    _ => raise InvalidGerber(source, "光圈定义参数无效")
  }
  let params = []
  for value in fields {
    params.push(aperture_number(value, source))
  }
  if state.macros.get(template) is Some(body) {
    state.apertures[code] = macro_aperture(
      template, body, params, scale, source,
    )
    return
  }
  state.apertures[code] = standard_aperture(template, params, scale, source)
}

///|
fn load_aperture_state(
  state : GerberState,
  operation : Char,
  value : String,
  source : String,
) -> Unit raise GerberError {
  match (operation, value) {
    ('P', "D") => state.dark = true
    ('P', "C") => state.dark = false
    ('M', "N" | "X" | "Y" | "XY") => {
      state.mirror_x = value == "X" || value == "XY"
      state.mirror_y = value == "Y" || value == "XY"
    }
    ('R', _) => state.aperture_angle = aperture_number(value, source)
    ('S', _) => {
      let scale = aperture_number(value, source)
      let area_scale = scale * scale
      if scale <= 0.0 || area_scale == 0.0 || area_scale.is_inf() {
        raise InvalidGerber(source, "LS 缩放因子超出可计算范围")
      }
      state.aperture_scale = scale
    }
    _ =>
      raise InvalidGerber(
        source,
        "无效的光圈状态指令 L\{operation}\{value}",
      )
  }
}

///|
fn aperture_matrix(state : GerberState) -> Transform2D {
  let rotation = aperture_rotation(state.aperture_angle)
  let sx = if state.mirror_x {
    -state.aperture_scale
  } else {
    state.aperture_scale
  }
  let sy = if state.mirror_y {
    -state.aperture_scale
  } else {
    state.aperture_scale
  }
  {
    a: rotation.a * sx,
    b: rotation.b * sy,
    c: 0.0,
    d: rotation.d * sx,
    e: rotation.e * sy,
    f: 0.0,
  }
}

///|
fn parse_attribute(state : GerberState, chars : Array[Char]) -> Unit {
  if chars.length() < 5 || chars[2] != '.' || chars[4] != ',' {
    return
  }
  let value = StringBuilder()
  let mut end = 5
  for index in 5..<chars.length() {
    if chars[index] == ',' {
      break
    }
    value.write_char(chars[index])
    end = index + 1
  }
  let refdes = value.to_string()
  let attribute = if refdes.is_empty() { None } else { Some(refdes) }
  match chars[3] {
    'C' => state.refdes = attribute
    'P' => {
      state.pin_refdes = attribute
      state.pin_name = None
      let start = end + 1
      let pin = StringBuilder()
      for i in start..<chars.length() {
        if chars[i] == ',' {
          break
        }
        pin.write_char(chars[i])
      }
      let pin = pin.to_string()
      if attribute is Some(_) && !pin.is_empty() {
        state.pin_name = Some(pin)
      }
    }
    _ => ()
  }
}

///|
fn feature_refdes(state : GerberState) -> String? {
  match state.pin_refdes {
    Some(_) => state.pin_refdes
    None => state.refdes
  }
}

///|
fn is_number_char(ch : Char) -> Bool {
  is_digit(ch) || ch == '-' || ch == '+' || ch == '.'
}

///|
fn gerber_words(chars : Array[Char]) -> Array[GerberWord] {
  let words : Array[GerberWord] = []
  let mut index = 0
  while index < chars.length() {
    let letter = chars[index]
    index += 1
    let buffer = StringBuilder()
    while index < chars.length() && is_number_char(chars[index]) {
      buffer.write_char(chars[index])
      index += 1
    }
    words.push({ letter, value: buffer.to_string(), })
  }
  words
}

///|
fn coordinate(
  state : GerberState,
  word : GerberWord,
  source : String,
) -> Double raise GerberError {
  guard state.format is Some(format) else {
    raise InvalidGerber(source, "坐标前缺少 FS 格式声明")
  }
  guard state.scale is Some(scale) else {
    raise InvalidGerber(source, "坐标前缺少 MO 单位声明")
  }
  let mut digits = 0
  let mut value = 0.0
  let mut negative = false
  for index, ch in word.value.iter2() {
    if index == 0 && (ch == '+' || ch == '-') {
      negative = ch == '-'
    } else if is_digit(ch) && digits < format.digits {
      value = value * 10.0 + digit_value(ch).to_double()
      digits += 1
    } else {
      raise InvalidGerber(
        source,
        "无效或超出 FS 位宽的坐标：\{word.letter}\{word.value}",
      )
    }
  }
  if digits == 0 {
    raise InvalidGerber(
      source,
      "坐标缺少数值：\{word.letter}\{word.value}",
    )
  }
  let omitted = if format.trailing_zeros_omitted {
    format.digits - digits
  } else {
    0
  }
  let mm = value * pow10(omitted) / pow10(format.decimals) * scale
  if negative {
    -mm
  } else {
    mm
  }
}

///|
fn current_aperture(
  state : GerberState,
  source : String,
) -> Aperture raise GerberError {
  match state.apertures.get(state.current_aperture) {
    Some(shape) => shape
    None if state.blocks.contains(state.current_aperture) =>
      raise InvalidGerber(
        source, "AB 块光圈仅用于 D03，不能用于 D01",
      )
    None => raise InvalidGerber(source, "未选择光圈")
  }
}

///|
fn flush_region(state : GerberState, source : String) -> Unit raise GerberError {
  if !state.region {
    raise InvalidGerber(source, "G37 前缺少 G36")
  }
  close_region_contour(state, source)
  let contours = state.region_contours
  let mut bounds = contours[0].bounds
  for contour in contours {
    bounds = bounds.union(contour.bounds)
  }
  state.emit(
    {
      kind: Region({ contours, bounds, }),
      dark: state.dark,
      refdes: feature_refdes(state),
      pin: state.pin_name,
      statement_number: state.statement_number,
      block_instance: None,
    },
    source,
  )
  state.region = false
  state.region_contours = []
}

///|
fn process_operation(
  state : GerberState,
  chars : Array[Char],
  statement : String,
  source : String,
) -> Unit raise GerberError {
  if statement.has_prefix("G04") {
    return
  }
  let words = gerber_words(chars)
  let mut x : Double? = None
  let mut y : Double? = None
  let mut operation = -1
  let mut i_offset : Double? = None
  let mut j_offset : Double? = None
  for word in words {
    match word.letter {
      'G' => {
        let code = parse_code(word, source)
        match code {
          1 => state.interpolation = 1
          2 => state.interpolation = 2
          3 => state.interpolation = 3
          36 => {
            if state.region {
              raise InvalidGerber(source, "铜区内不能嵌套 G36")
            }
            state.region = true
            state.region_points = []
            state.region_error = 0.0
            state.region_contours = []
            state.region_vertices = 0
          }
          37 => flush_region(state, source)
          70 | 71 | 91 =>
            raise InvalidGerber(
              source, "不支持旧版单位或增量坐标指令，请以 FS 和 MO 声明",
            )
          74 | 75 => state.quadrant_mode = code
          54 | 55 | 90 => ()
          _ =>
            raise InvalidGerber(
              source,
              "暂不支持的绘图指令：G\{word.value}",
            )
        }
      }
      'X' => x = Some(coordinate(state, word, source))
      'Y' => y = Some(coordinate(state, word, source))
      'I' => i_offset = Some(coordinate(state, word, source))
      'J' => j_offset = Some(coordinate(state, word, source))
      'D' => {
        let code = parse_code(word, source)
        if code >= 10 {
          if state.region {
            raise InvalidGerber(source, "铜区轮廓中不能切换光圈")
          }
          state.current_aperture = code
        } else if code >= 1 && code <= 3 {
          operation = code
        } else {
          raise InvalidGerber(source, "不支持的 D 指令：\{word.value}")
        }
      }
      _ =>
        raise InvalidGerber(source, "无法读取绘图指令：\{statement}")
    }
  }
  if operation == -1 {
    if x is Some(_) ||
      y is Some(_) ||
      i_offset is Some(_) ||
      j_offset is Some(_) {
      raise InvalidGerber(
        source,
        "坐标缺少 D01、D02 或 D03 指令：\{statement}",
      )
    }
    return
  }
  let target = match (x, y, state.current) {
    (Some(x), Some(y), _) => { x, y, }
    (x, y, Some(start)) => { x: x.unwrap_or(start.x), y: y.unwrap_or(start.y), }
    _ =>
      raise InvalidGerber(
        source, "当前位置未定义，请先给出完整 X/Y 坐标",
      )
  }
  match operation {
    1 => {
      guard state.current is Some(start) else {
        raise InvalidGerber(source, "绘线前缺少起点")
      }
      let offset : Point? = if state.interpolation != 1 {
        if state.quadrant_mode == 74 {
          raise InvalidGerber(
            source, "暂不支持旧版 G74 单象限圆弧，请导出 G75",
          )
        }
        if state.quadrant_mode != 75 {
          raise InvalidGerber(source, "圆弧绘制前必须声明 G75")
        }
        Some({ x: i_offset.unwrap_or(0.0), y: j_offset.unwrap_or(0.0), })
      } else {
        None
      }
      if state.region {
        if state.region_points.is_empty() {
          raise InvalidGerber(
            source, "铜区轮廓必须先用 D02 指定起点",
          )
        }
        let previous = state.region_points.length()
        if offset is Some(offset) {
          let arc = make_gerber_arc(
            start,
            target,
            offset,
            state.interpolation == 2,
            0.0,
            source,
          )
          state.region_error = state.region_error.max(
            append_region_arc(state.region_points, arc, target),
          )
        } else {
          state.region_points.push(target)
        }
        state.region_vertices += state.region_points.length() - previous
        if state.region_vertices > 200000 {
          raise InvalidGerber(source, "铜区轮廓超过 200000 个顶点")
        }
      } else {
        let aperture = current_aperture(state, source)
        if !aperture.can_draw {
          raise InvalidGerber(
            source, "区域以外的 D01 需要实心圆形标准光圈",
          )
        }
        let shape = transform_shape(aperture.shape, aperture_matrix(state))
        if shape.area().is_inf() || shape.area().is_nan() {
          raise InvalidGerber(source, "描线光圈面积超出可计算范围")
        }
        state.emit(
          {
            kind: match offset {
              Some(offset) =>
                Arc(
                  make_gerber_arc(
                    start,
                    target,
                    offset,
                    state.interpolation == 2,
                    shape.bounding_radius(),
                    source,
                  ),
                )
              None => Draw(shape, start, target)
            },
            dark: state.dark,
            refdes: feature_refdes(state),
            pin: state.pin_name,
            statement_number: state.statement_number,
            block_instance: None,
          },
          source,
        )
      }
    }
    2 =>
      if state.region {
        if !state.region_points.is_empty() {
          close_region_contour(state, source)
        }
        state.region_points.push(target)
      }
    3 => {
      if state.region {
        raise InvalidGerber(source, "区域轮廓中不能使用 D03")
      }
      if state.blocks.get(state.current_aperture) is Some(contents) {
        flash_block(state, contents, target, source)
        state.current = Some(target)
        return
      }
      let aperture = current_aperture(state, source)
      let matrix = aperture_matrix(state)
      let offset = matrix.apply(aperture.offset)
      let center = { x: target.x + offset.x, y: target.y + offset.y, }
      let shape = transform_shape(aperture.shape, matrix)
      let area = shape.area()
      if area.is_inf() ||
        area.is_nan() ||
        center.x.is_nan() ||
        center.x.is_inf() ||
        center.y.is_nan() ||
        center.y.is_inf() {
        raise InvalidGerber(source, "闪光几何超出可计算范围")
      }
      state.emit(
        {
          kind: Flash(shape, center),
          dark: state.dark,
          refdes: feature_refdes(state),
          pin: state.pin_name,
          statement_number: state.statement_number,
          block_instance: None,
        },
        source,
      )
    }
    _ => ()
  }
  state.current = Some(target)
}

///|
fn process_statement(
  state : GerberState,
  statement : String,
  source : String,
) -> Unit raise GerberError {
  let chars = to_chars(statement)
  if chars.length() == 0 {
    return
  }
  if state.region &&
    !(chars[0] == 'G' ||
    chars[0] == 'D' ||
    chars[0] == 'X' ||
    chars[0] == 'Y' ||
    chars[0] == 'I' ||
    chars[0] == 'J') {
    raise InvalidGerber(
      source,
      "铜区内不能改变光圈、极性或属性：\{statement}",
    )
  }
  if chars.length() >= 2 {
    match (chars[0], chars[1]) {
      ('F', 'S') => return parse_format(state, chars, source)
      ('M', 'O') => return parse_units(state, statement, source)
      ('A', 'D') => return parse_aperture(state, chars, source)
      ('L', operation) =>
        return load_aperture_state(
          state,
          operation,
          chars_to_string(chars, 2),
          source,
        )
      ('A', 'M') => {
        let fields = aperture_fields(chars_to_string(chars, 2), '*')
        guard fields is [name, .. body] &&
          !name.is_empty() &&
          body.length() >= 2 &&
          body.get(body.length() - 1) == Some("") else {
          raise InvalidGerber(source, "无效的光圈宏定义")
        }
        state.macros[name] = body.to_owned()
        return
      }
      ('S', 'R') =>
        return parse_repeat(
          state,
          to_chars(chars_to_string(chars, 2)),
          statement,
          source,
        )
      ('A', 'B') => return parse_block(state, chars_to_string(chars, 2), source)
      ('A', 'S')
      | ('M', 'I')
      | ('O', 'F')
      | ('S', 'F')
      | ('I', 'R')
      | ('I', 'P') =>
        raise InvalidGerber(
          source,
          "暂不支持会改变铜层几何的指令：\{statement}",
        )
      ('T', 'O') => {
        // Accept the old example's nonstandard reset spelling as well as TD.
        if chars_to_string(chars, 2) == ".D" {
          state.refdes = None
          state.pin_refdes = None
          state.pin_name = None
        } else {
          parse_attribute(state, chars)
        }
        return
      }
      ('T', 'D') => {
        match chars_to_string(chars, 2) {
          "" => {
            state.refdes = None
            state.pin_refdes = None
            state.pin_name = None
          }
          ".C" => state.refdes = None
          ".P" => {
            state.pin_refdes = None
            state.pin_name = None
          }
          _ => ()
        }
        return
      }
      ('T', 'F') => {
        if statement == "TF.FilePolarity,Negative" {
          raise InvalidGerber(source, "暂不支持负像铜层核验")
        }
        return
      }
      ('T', 'A') => return
      _ => ()
    }
  }
  match chars[0] {
    'G' | 'D' | 'X' | 'Y' | 'I' | 'J' =>
      process_operation(state, chars, statement, source)
    _ =>
      raise InvalidGerber(
        source,
        "暂不支持的 Gerber 指令：\{statement}",
      )
  }
}

///|
/// Parse an RS-274X Gerber file.
///
/// Reads standard apertures, selected macros, flashes, strokes, regions,
/// block apertures, step repeats, polarity and X2 component/pin attributes.
pub fn parse_gerber(
  text : String,
  source~ : String,
) -> GerberDocument raise GerberError {
  let (document, _) = parse_gerber_layer(text, source, keep_panel_base=false)
  document
}

///|
fn parse_gerber_layer(
  text : String,
  source : String,
  keep_panel_base~ : Bool,
) -> (GerberDocument, (Int32, Int32)?) raise GerberError {
  let state : GerberState = {
    format: None,
    scale: None,
    apertures: Map([]),
    macros: Map([]),
    current_aperture: 0,
    mirror_x: false,
    mirror_y: false,
    aperture_angle: 0.0,
    aperture_scale: 1.0,
    dark: true,
    current: None,
    interpolation: 1,
    quadrant_mode: 0,
    region: false,
    region_points: [],
    region_error: 0.0,
    region_contours: [],
    region_vertices: 0,
    refdes: None,
    pin_refdes: None,
    pin_name: None,
    statement_number: 0,
    features: [],
    warnings: [],
    repeat: None,
    repeat_budget: 200000,
    keep_panel_base,
    panel_base: None,
    panel_grids: [],
    blocks: Map([]),
    block_stack: [],
    block_budget: 200000,
    block_seen_refs: Map([]),
    block_instances: 0,
    repeated_refs: Map([]),
  }
  for index, statement in split_statements(text, source) {
    if statement == "M02" {
      break
    }
    state.statement_number = index + 1
    process_statement(state, statement, source)
  }
  if state.region {
    raise InvalidGerber(source, "区域缺少结束指令 G37")
  }
  if state.repeat is Some(_) {
    raise InvalidGerber(source, "步进重复缺少结束指令 SR")
  }
  if !state.block_stack.is_empty() {
    raise InvalidGerber(source, "块光圈缺少结束指令 AB")
  }
  if state.features.any(feature => !feature.dark) {
    state.warnings.push(
      "清除对象按保守范围确定可能受影响的焊盘",
    )
  }
  if !state.repeated_refs.is_empty() {
    state.warnings.push(repeated_reference_warning)
  }
  let document : GerberDocument = {
    features: state.features,
    warnings: state.warnings,
    repeated_refs: state.repeated_refs,
    panel_grids: state.panel_grids,
    panel_cell: None,
  }
  (document, state.panel_base)
}
