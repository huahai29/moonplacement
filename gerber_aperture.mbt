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
  } else if shape is Transformed(inner, first) {
    // These aperture transforms have no translation. Compose them so a deep
    // chain of block definitions never creates a deep runtime shape.
    Transformed(inner, {
      a: matrix.a * first.a + matrix.b * first.d,
      b: matrix.a * first.b + matrix.b * first.e,
      c: 0.0,
      d: matrix.d * first.a + matrix.e * first.d,
      e: matrix.d * first.b + matrix.e * first.e,
      f: 0.0,
    })
  } else {
    Transformed(shape, matrix)
  }
}

///|
fn aperture_rotation(angle : Double) -> Transform2D {
  Transform2D::rotation(angle % 360.0, { x: 0.0, y: 0.0, })
}

///|
fn aperture_origin() -> Point {
  { x: 0.0, y: 0.0, }
}

///|
/// Distance from an interior point to the nearest outer edge, in local
/// coordinates. Negative values are outside the aperture.
fn hole_clearance(shape : Shape, hole : Point) -> Double {
  match shape {
    Circle(radius) => radius - @math.hypot(hole.x, hole.y)
    Rectangle(width, height) =>
      (width * 0.5 - hole.x.abs()).min(height * 0.5 - hole.y.abs())
    Obround(width, height) => {
      let (along, across) = if width >= height {
        (hole.x, hole.y)
      } else {
        (hole.y, hole.x)
      }
      let straight = (width - height).abs() * 0.5
      width.min(height) * 0.5 -
      @math.hypot((along.abs() - straight).max(0.0), across)
    }
    // Standard polygon holes are concentric.
    Polygon(radius, sides) => radius * @math.cos(@math.PI / sides.to_double())
    Outline(points) => {
      if !polygon_contains(points, hole) {
        return 0.0
      }
      let mut clearance = magnitude(difference(hole, points[0]))
      for i in 0..<points.length() {
        clearance = clearance.min(
          segment_distance(hole, points[i], points[(i + 1) % points.length()]),
        )
      }
      clearance
    }
    _ => 0.0
  }
}

///|
fn subtract_round_hole(
  shape : Shape,
  hole : Point,
  radius : Double,
  source : String,
  template : String,
) -> (Shape, Point) raise GerberError {
  let clearance = hole_clearance(shape, hole)
  let hole_area = @math.PI * radius * radius
  let copper_area = shape.area() - hole_area
  if !(radius > 0.0 &&
    radius < clearance &&
    hole_area > 0.0 &&
    copper_area > 0.0) ||
    copper_area.is_inf() {
    raise InvalidGerber(
      source,
      "圆孔必须有正直径且完全位于光圈内部：\{template}",
    )
  }
  let ratio = hole_area / copper_area
  let center : Point = { x: -hole.x * ratio, y: -hole.y * ratio, }
  let relative_hole : Point = { x: hole.x - center.x, y: hole.y - center.y, }
  if relative_hole.x.is_nan() ||
    relative_hole.x.is_inf() ||
    relative_hole.y.is_nan() ||
    relative_hole.y.is_inf() {
    raise InvalidGerber(
      source,
      "带孔光圈中心超出可计算范围：\{template}",
    )
  }
  (
    RoundHole(shape, { x: -center.x, y: -center.y, }, relative_hole, radius),
    center,
  )
}

///|
fn standard_aperture(
  template : String,
  params : Array[Double],
  unit : Double,
  source : String,
) -> Aperture raise GerberError {
  let (shape, angle, hole) = match (template, params) {
    ("C", [diameter, .. tail]) if diameter >= 0.0 && tail.length() <= 1 =>
      (Circle(diameter * unit * 0.5), 0.0, tail.get(0))
    ("R" | "O", [width, height, .. tail]) if width >= 0.0 &&
      height >= 0.0 &&
      tail.length() <= 1 => {
      let x = width * unit
      let y = height * unit
      (
        if template == "R" {
          Rectangle(x, y)
        } else {
          Obround(x, y)
        },
        0.0,
        tail.get(0),
      )
    }
    ("P", [diameter, sides, .. tail]) if diameter >= 0.0 &&
      sides >= 3.0 &&
      sides <= 12.0 &&
      sides == sides.to_int().to_double() &&
      tail.length() <= 2 =>
      (
        Polygon(diameter * unit * 0.5, sides.to_int()),
        tail.get(0).unwrap_or(0.0),
        tail.get(1),
      )
    _ =>
      raise InvalidGerber(
        source,
        "暂不支持的光圈模板或参数：\{template}",
      )
  }
  let shape = match hole {
    Some(diameter) =>
      subtract_round_hole(
        shape,
        aperture_origin(),
        diameter * unit * 0.5,
        source,
        template,
      ).0
    None => shape
  }
  {
    shape: transform_shape(shape, aperture_rotation(angle)),
    offset: aperture_origin(),
    can_draw: template == "C" && hole is None,
  }
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
  match primitives {
    [_, [1.0, 0.0, ..], .. rest] if rest
      .iter()
      .all(cut => cut is [1.0, 0.0, ..]) => ()
    [_, _, ..] => return rounded_macro(name, primitives, unit, source)
    _ => ()
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
    Some([4.0, 1.0, count, ..]) =>
      outline_macro(primitives[0], count, unit, source, name)
    Some([5.0, 1.0, sides, x, y, diameter, angle]) if sides >= 3.0 &&
      sides <= 12.0 &&
      sides == sides.to_int().to_double() &&
      diameter > 0.0 =>
      (
        Polygon(diameter * unit * 0.5, sides.to_int()),
        { x: x * unit, y: y * unit, },
        angle,
      )
    Some([20.0, 1.0, width, ax, ay, bx, by, angle]) if width > 0.0 => {
      let dx = (bx - ax) * unit
      let dy = (by - ay) * unit
      let length = @math.hypot(dx, dy)
      let center : Point = {
        x: (ax * 0.5 + bx * 0.5) * unit,
        y: (ay * 0.5 + by * 0.5) * unit,
      }
      (
        transform_shape(
          Rectangle(length, width * unit),
          aperture_rotation(@math.atan2(dy, dx) * 180.0 / @math.PI),
        ),
        center,
        angle,
      )
    }
    Some([7.0, x, y, outer, inner, gap, angle]) if outer > inner &&
      inner >= 0.0 &&
      gap > 0.0 &&
      gap < outer / 2.0.sqrt() =>
      (
        Thermal(outer * unit * 0.5, inner * unit * 0.5, gap * unit * 0.5),
        { x: x * unit, y: y * unit, },
        angle,
      )
    _ =>
      raise InvalidGerber(
        source,
        "暂不支持光圈宏图元或表达式：\{name}",
      )
  }
  let rotation = aperture_rotation(angle)
  if primitives.length() > 2 {
    return punched_macro(
      shape,
      rotation.apply(offset),
      angle,
      primitives[1:],
      unit,
      source,
      name,
    )
  }
  if primitives.get(1) is Some([1.0, 0.0, diameter, x, y, .. trailing]) &&
    trailing.length() <= 1 {
    let clear = aperture_rotation(trailing.get(0).unwrap_or(0.0)).apply({
      x: x * unit,
      y: y * unit,
    })
    let solid = rotation.apply(offset)
    let hole = aperture_rotation(-angle).apply({
      x: clear.x - solid.x,
      y: clear.y - solid.y,
    })
    let (punched, shift) = subtract_round_hole(
      shape,
      hole,
      diameter * unit * 0.5,
      source,
      name,
    )
    let shift = rotation.apply(shift)
    return {
      shape: transform_shape(punched, rotation),
      offset: { x: solid.x + shift.x, y: solid.y + shift.y, },
      can_draw: false,
    }
  }
  if primitives.length() == 2 {
    raise InvalidGerber(source, "圆形清除图元的参数无效：\{name}")
  }
  {
    shape: transform_shape(shape, rotation),
    offset: rotation.apply(offset),
    can_draw: false,
  }
}
