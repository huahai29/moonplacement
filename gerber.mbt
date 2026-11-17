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
priv struct GerberState {
  mut decimal_digits : Int32
  mut scale : Double
  apertures : Map[Int32, Shape]
  mut current_aperture : Int32
  mut dark : Bool
  mut current : Point
  mut interpolation : Int32
  mut region : Bool
  mut region_points : Array[Point]
  mut refdes : String?
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
fn parse_code(value : String) -> Int32 {
  parse_number(value).to_int()
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
  let mut index = 2
  if index < chars.length() &&
    (chars[index] == 'L' || chars[index] == 'T' || chars[index] == 'D') {
    index += 1
  }
  if index < chars.length() && (chars[index] == 'A' || chars[index] == 'I') {
    index += 1
  }
  while index + 2 < chars.length() {
    let axis = chars[index]
    if axis == 'X' || axis == 'Y' {
      state.decimal_digits = digit_value(chars[index + 2])
    }
    index += 3
  }
  if state.decimal_digits < 0 || state.decimal_digits > 9 {
    raise InvalidGerber(source, "坐标格式的小数位无效")
  }
}

///|
fn parse_units(state : GerberState, chars : Array[Char]) -> Unit {
  if chars.length() >= 4 && chars[2] == 'M' && chars[3] == 'M' {
    state.scale = 1.0
  } else if chars.length() >= 4 && chars[2] == 'I' && chars[3] == 'N' {
    state.scale = 25.4
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
  let params = parse_params(chars, index, state.scale)
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
  if chars.length() >= 4 && chars[2] == '.' {
    match chars[3] {
      'C' => {
        let value = if chars.length() > 5 {
          chars_to_string(chars, 5)
        } else {
          ""
        }
        if !value.is_empty() {
          state.refdes = Some(value)
        }
      }
      'D' => state.refdes = None
      _ => ()
    }
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
fn coordinate(state : GerberState, text : String) -> Double {
  parse_number(text) / pow10(state.decimal_digits) * state.scale
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
      refdes: state.refdes,
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
  let words = gerber_words(chars)
  let mut has_x = false
  let mut has_y = false
  let mut target_x = state.current.x
  let mut target_y = state.current.y
  let mut operation = -1
  let mut comment = false
  for word in words {
    match word.letter {
      'G' => {
        let code = parse_code(word.value)
        match code {
          4 => comment = true
          1 => state.interpolation = 1
          2 => state.interpolation = 2
          3 => state.interpolation = 3
          36 => {
            state.region = true
            state.region_points = []
          }
          37 => flush_region(state)
          74 | 75 => ()
          _ => ()
        }
      }
      'X' => {
        target_x = coordinate(state, word.value)
        has_x = true
      }
      'Y' => {
        target_y = coordinate(state, word.value)
        has_y = true
      }
      'I' | 'J' => ()
      'D' => {
        let code = parse_code(word.value)
        if code >= 10 {
          state.current_aperture = code
        } else {
          operation = code
        }
      }
      'M' => if parse_code(word.value) == 2 { return }
      _ => ()
    }
  }
  if comment {
    return
  }
  if !has_x && !has_y {
    return
  }
  let target = { x: target_x, y: target_y, }
  match operation {
    1 => {
      if state.interpolation != 1 {
        state.warnings.push("圆弧已按弦线近似：\{statement}")
      }
      if state.region {
        state.region_points.push(state.current)
        state.region_points.push(target)
      } else {
        let shape = current_shape(state, source)
        state.features.push({
          kind: Draw(shape, state.current, target),
          dark: state.dark,
          refdes: state.refdes,
        })
      }
    }
    2 => ()
    3 => {
      let shape = current_shape(state, source)
      state.features.push({
        kind: Flash(shape, target),
        dark: state.dark,
        refdes: state.refdes,
      })
    }
    _ => ()
  }
  state.current = target
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
      ('M', 'O') => return parse_units(state, chars)
      ('A', 'D') => return parse_aperture(state, chars, source)
      ('L', 'P') => return parse_polarity(state, chars)
      ('A', 'M') => {
        state.warnings.push("跳过光圈宏：\{statement}")
        return
      }
      ('T', 'O') => return parse_attribute(state, chars)
      ('T', 'D') => {
        state.refdes = None
        return
      }
      ('T', 'F') | ('T', 'A') => return
      _ => ()
    }
  }
  process_operation(state, chars, statement, source)
}

///|
/// Parse an RS-274X Gerber file.
///
/// Supported: format spec, mm/inch units, `C`/`R`/`O`/`P` apertures, `G01`
/// linear interpolation, `D01`/`D02`/`D03`, `G36`/`G37` regions, `LPD`/`LPC`
/// polarity and X2 `TO.C` component attributes. Aperture macros and arcs are
/// approximated and reported through `warnings`.
pub fn parse_gerber(
  text : String,
  source~ : String,
) -> GerberDocument raise GerberError {
  let state : GerberState = {
    decimal_digits: 4,
    scale: 1.0,
    apertures: Map([]),
    current_aperture: 0,
    dark: true,
    current: { x: 0.0, y: 0.0, },
    interpolation: 1,
    region: false,
    region_points: [],
    refdes: None,
    features: [],
    warnings: [],
  }
  for statement in split_statements(text) {
    process_statement(state, statement, source)
  }
  { features: state.features, warnings: state.warnings, }
}
