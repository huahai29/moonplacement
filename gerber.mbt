///|
/// Raised when a Gerber file cannot be interpreted.
pub(all) suberror GerberError {
  InvalidGerber(String, String)
}

///|
/// One parsed Gerber drawing operation.
pub enum GerberKind {
  /// An aperture flashed at a point (`D03`), the usual representation of a pad.
  Flash(Shape, Point)
  /// A stroked segment (`D01`) with the current aperture as its width.
  Draw(Shape, Point, Point)
  /// A filled region built from `G36`/`G37`.
  Region(Array[Point])
}

///|
/// A single feature with the X2 component attribution (if present) and the
/// polarity active when it was drawn.
pub struct GerberFeature {
  kind : GerberKind
  dark : Bool
  refdes : String?
}

///|
/// Parsed Gerber layer. `warnings` records constructs that were intentionally
/// approximated or skipped so callers can surface them.
pub struct GerberDocument {
  features : Array[GerberFeature]
  warnings : Array[String]
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
  apertures : Map[Int32, Shape]
  mut current_aperture : Int32
  mut dark : Bool
  mut current : Point?
  mut interpolation : Int32
  mut region : Bool
  mut region_points : Array[Point]
  mut refdes : String?
  mut pin_refdes : String?
  features : Array[GerberFeature]
  warnings : Array[String]
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
fn split_statements(text : String) -> Array[String] {
  let statements : Array[String] = []
  let mut buffer = StringBuilder()
  for _, ch in text.iter2() {
    match ch {
      '*' => {
        let statement = buffer.to_string()
        if !statement.is_empty() {
          statements.push(statement)
        }
        buffer = StringBuilder()
      }
      '%' | '\r' | '\n' | '\t' | ' ' => ()
      _ => buffer.write_char(ch)
    }
  }
  let tail = buffer.to_string()
  if !tail.is_empty() {
    statements.push(tail)
  }
  statements
}

///|
fn parse_number(text : String) -> Double {
  @string.parse_double(text) catch {
    _ => 0.0
  }
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
fn parse_params(
  chars : Array[Char],
  start : Int32,
  scale : Double,
) -> Array[Double] {
  let params : Array[Double] = []
  let mut index = start
  let mut buffer = StringBuilder()
  while index < chars.length() {
    let ch = chars[index]
    if ch == 'X' || ch == 'x' {
      let part = buffer.to_string()
      if !part.is_empty() {
        params.push(parse_number(part) * scale)
        buffer = StringBuilder()
      }
    } else {
      buffer.write_char(ch)
    }
    index += 1
  }
  let part = buffer.to_string()
  if !part.is_empty() {
    params.push(parse_number(part) * scale)
  }
  params
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
  let template = chars[index]
  index += 1
  if index >= chars.length() || chars[index] != ',' {
    raise InvalidGerber(source, "光圈参数缺少逗号")
  }
  index += 1
  guard state.scale is Some(scale) else {
    raise InvalidGerber(source, "光圈定义前缺少 MO 单位声明")
  }
  let params = parse_params(chars, index, scale)
  let shape = match template {
    'C' => {
      if params.length() < 1 {
        raise InvalidGerber(source, "圆形光圈缺少直径")
      }
      Circle(params[0] * 0.5)
    }
    'R' => {
      if params.length() < 2 {
        raise InvalidGerber(source, "矩形光圈缺少宽高")
      }
      Rectangle(params[0], params[1])
    }
    'O' => {
      if params.length() < 2 {
        raise InvalidGerber(source, "椭圆形光圈缺少宽高")
      }
      Obround(params[0], params[1])
    }
    'P' => {
      if params.length() < 2 {
        raise InvalidGerber(source, "多边形光圈缺少直径或边数")
      }
      Polygon(params[0] * 0.5, params[1].to_int())
    }
    _ => raise InvalidGerber(source, "不支持的光圈模板")
  }
  state.apertures[code] = shape
}

///|
fn parse_polarity(state : GerberState, chars : Array[Char]) -> Unit {
  if chars.length() >= 3 {
    state.dark = chars[2] != 'C'
  }
}

///|
fn parse_attribute(state : GerberState, chars : Array[Char]) -> Unit {
  if chars.length() < 5 || chars[2] != '.' || chars[4] != ',' {
    return
  }
  let value = StringBuilder()
  for index in 5..<chars.length() {
    if chars[index] == ',' {
      break
    }
    value.write_char(chars[index])
  }
  let refdes = value.to_string()
  let attribute = if refdes.is_empty() { None } else { Some(refdes) }
  match chars[3] {
    'C' => state.refdes = attribute
    'P' => state.pin_refdes = attribute
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
fn current_shape(
  state : GerberState,
  source : String,
) -> Shape raise GerberError {
  match state.apertures.get(state.current_aperture) {
    Some(shape) => shape
    None => raise InvalidGerber(source, "未选择光圈")
  }
}

///|
fn flush_region(state : GerberState) -> Unit {
  state.region = false
  if state.region_points.length() >= 3 {
    state.features.push({
      kind: Region(state.region_points),
      dark: state.dark,
      refdes: feature_refdes(state),
    })
  }
  state.region_points = []
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
  let mut has_offset = false
  for word in words {
    match word.letter {
      'G' => {
        let code = parse_code(word, source)
        match code {
          1 => state.interpolation = 1
          2 => state.interpolation = 2
          3 => state.interpolation = 3
          36 => {
            state.region = true
            state.region_points = []
          }
          37 => flush_region(state)
          91 =>
            raise InvalidGerber(
              source, "不支持增量坐标，请重新导出为绝对坐标",
            )
          74 | 75 => ()
          _ => ()
        }
      }
      'X' => x = Some(coordinate(state, word, source))
      'Y' => y = Some(coordinate(state, word, source))
      'I' | 'J' => {
        let _ = coordinate(state, word, source)
        has_offset = true
      }
      'D' => {
        let code = parse_code(word, source)
        if code >= 10 {
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
    if x is Some(_) || y is Some(_) || has_offset {
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
      if state.interpolation != 1 {
        state.warnings.push("圆弧已按弦线近似：\{statement}")
      }
      if state.region {
        state.region_points.push(start)
        state.region_points.push(target)
      } else {
        let shape = current_shape(state, source)
        state.features.push({
          kind: Draw(shape, start, target),
          dark: state.dark,
          refdes: feature_refdes(state),
        })
      }
    }
    2 => ()
    3 => {
      if state.region {
        raise InvalidGerber(source, "区域轮廓中不能使用 D03")
      }
      let shape = current_shape(state, source)
      state.features.push({
        kind: Flash(shape, target),
        dark: state.dark,
        refdes: feature_refdes(state),
      })
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
  if chars.length() >= 2 {
    match (chars[0], chars[1]) {
      ('F', 'S') => return parse_format(state, chars, source)
      ('M', 'O') => return parse_units(state, statement, source)
      ('A', 'D') => return parse_aperture(state, chars, source)
      ('L', 'P') => return parse_polarity(state, chars)
      ('A', 'M') => {
        state.warnings.push("跳过光圈宏：\{statement}")
        return
      }
      ('T', 'O') => {
        // Accept the old example's nonstandard reset spelling as well as TD.
        if chars_to_string(chars, 2) == ".D" {
          state.refdes = None
          state.pin_refdes = None
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
          }
          ".C" => state.refdes = None
          ".P" => state.pin_refdes = None
          _ => ()
        }
        return
      }
      ('T', 'F') | ('T', 'A') => return
      _ => ()
    }
  }
  match chars[0] {
    'G' | 'D' | 'X' | 'Y' | 'I' | 'J' =>
      process_operation(state, chars, statement, source)
    _ => ()
  }
}

///|
/// Parse an RS-274X Gerber file.
///
/// Supported: absolute coordinates with leading or trailing zero omission,
/// mm/inch units, `C`/`R`/`O`/`P` apertures, `G01`
/// linear interpolation, `D01`/`D02`/`D03`, `G36`/`G37` regions, `LPD`/`LPC`
/// polarity and X2 `TO.C` component / `TO.P` pin attributes. Macros and arcs are
/// approximated and reported through `warnings`.
pub fn parse_gerber(
  text : String,
  source~ : String,
) -> GerberDocument raise GerberError {
  let state : GerberState = {
    format: None,
    scale: None,
    apertures: Map([]),
    current_aperture: 0,
    dark: true,
    current: None,
    interpolation: 1,
    region: false,
    region_points: [],
    refdes: None,
    pin_refdes: None,
    features: [],
    warnings: [],
  }
  for statement in split_statements(text) {
    if statement == "M02" {
      break
    }
    process_statement(state, statement, source)
  }
  { features: state.features, warnings: state.warnings, }
}
