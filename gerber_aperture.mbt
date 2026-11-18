///|
priv struct Aperture {
  shape : Shape
  offset : Point
  can_draw : Bool
}

///|
fn aperture_number(value : String, source : String) -> Double raise GerberError {
  for _, ch in value.iter2() {
    if !is_number_char(ch) {
      raise InvalidGerber(
        source,
        "无效或暂不支持的光圈数值：\{value}",
      )
    }
  }
  let number = @string.parse_double(value) catch {
    _ => raise InvalidGerber(source, "无效的光圈数值：\{value}")
  }
  if number.is_nan() || number.is_inf() {
    raise InvalidGerber(source, "光圈数值超出可计算范围：\{value}")
  }
  number
}

///|
fn aperture_fields(text : String, separator : Char) -> Array[String] {
  let fields = []
  let buffer = StringBuilder()
  for _, ch in text.iter2() {
    if ch == separator {
      fields.push(buffer.to_string())
      buffer.reset()
    } else {
      buffer.write_char(ch)
    }
  }
  fields.push(buffer.to_string())
  fields
}

///|
fn macro_value(
  text : String,
  params : Array[Double],
  source : String,
) -> Double raise GerberError {
  let chars = to_chars(text)
  if chars.get(0) is Some('$') {
    let index = parse_code(
      { letter: '$', value: chars_to_string(chars, 1), },
      source,
    )
    if index < 1 {
      raise InvalidGerber(source, "光圈宏变量必须从 $1 开始")
    }
    return params.get(index - 1).unwrap_or(0.0)
  }
  aperture_number(text, source)
}

///|
fn transform_shape(shape : Shape, matrix : Transform2D) -> Shape {
  if matrix.a == 1.0 && matrix.b == 0.0 && matrix.d == 0.0 && matrix.e == 1.0 {
    shape
  } else {
    Transformed(shape, matrix)
  }
}

///|
fn aperture_rotation(angle : Double) -> Transform2D {
  Transform2D::rotation(angle % 360.0, { x: 0.0, y: 0.0, })
}

///|
fn macro_aperture(
  name : String,
  body : Array[String],
  params : Array[Double],
  unit : Double,
  source : String,
) -> Aperture raise GerberError {
  let mut primitive : Array[String]? = None
  for statement in body {
    if statement.is_empty() || statement.has_prefix("0") {
      continue
    }
    if primitive is Some(_) {
      raise InvalidGerber(source, "暂不支持多图元光圈宏：\{name}")
    }
    primitive = Some(aperture_fields(statement, ','))
  }
  let (shape, offset, angle) = match primitive {
    Some(["1", exposure, diameter, x, y, .. trailing]) if trailing.length() <= 1 => {
      if macro_value(exposure, params, source) != 1.0 {
        raise InvalidGerber(
          source,
          "暂不支持清除图元光圈宏：\{name}",
        )
      }
      let radius = macro_value(diameter, params, source) * unit * 0.5
      if radius < 0.0 {
        raise InvalidGerber(source, "光圈直径不能为负数：\{name}")
      }
      (
        Circle(radius),
        {
          x: macro_value(x, params, source) * unit,
          y: macro_value(y, params, source) * unit,
        },
        macro_value(trailing.get(0).unwrap_or("0"), params, source),
      )
    }
    Some(["21", exposure, width, height, x, y, angle]) => {
      if macro_value(exposure, params, source) != 1.0 {
        raise InvalidGerber(
          source,
          "暂不支持清除图元光圈宏：\{name}",
        )
      }
      let width = macro_value(width, params, source) * unit
      let height = macro_value(height, params, source) * unit
      if width < 0.0 || height < 0.0 {
        raise InvalidGerber(source, "光圈尺寸不能为负数：\{name}")
      }
      (
        Rectangle(width, height),
        {
          x: macro_value(x, params, source) * unit,
          y: macro_value(y, params, source) * unit,
        },
        macro_value(angle, params, source),
      )
    }
    _ =>
      raise InvalidGerber(
        source,
        "暂不支持光圈宏图元或表达式：\{name}",
      )
  }
  let rotation = aperture_rotation(angle)
  {
    shape: transform_shape(shape, rotation),
    offset: rotation.apply(offset),
    can_draw: false,
  }
}
