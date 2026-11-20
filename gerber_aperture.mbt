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
  let variables : Map[Int32, Double] = Map([])
  for i, value in params {
    variables[i + 1] = value
  }
  let primitives : Array[Array[Double]] = []
  for statement in body {
    if statement.is_empty() || statement.has_prefix("0") {
      continue
    }
    if statement.has_prefix("$") {
      macro_assign(statement, variables, source)
      continue
    }
    let values = []
    for i, field in aperture_fields(statement, ',') {
      if i == 0 {
        values.push(
          parse_code({ letter: 'A', value: field, }, source).to_double(),
        )
        continue
      }
      values.push(macro_value(field, variables, source))
    }
    primitives.push(values)
  }
  if primitives.length() > 1 {
    return rounded_macro(name, primitives, unit, source)
  }
  let (shape, offset, angle) = match primitives.get(0) {
    Some([1.0, exposure, diameter, x, y, .. trailing]) if trailing.length() <= 1 => {
      if exposure != 1.0 {
        raise InvalidGerber(
          source,
          "暂不支持清除图元光圈宏：\{name}",
        )
      }
      let radius = diameter * unit * 0.5
      if radius < 0.0 {
        raise InvalidGerber(source, "光圈直径不能为负数：\{name}")
      }
      (
        Circle(radius),
        { x: x * unit, y: y * unit, },
        trailing.get(0).unwrap_or(0.0),
      )
    }
    Some([21.0, exposure, width, height, x, y, angle]) => {
      if exposure != 1.0 {
        raise InvalidGerber(
          source,
          "暂不支持清除图元光圈宏：\{name}",
        )
      }
      let width = width * unit
      let height = height * unit
      if width < 0.0 || height < 0.0 {
        raise InvalidGerber(source, "光圈尺寸不能为负数：\{name}")
      }
      (Rectangle(width, height), { x: x * unit, y: y * unit, }, angle)
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
