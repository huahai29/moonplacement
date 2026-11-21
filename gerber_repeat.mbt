///|
priv struct GerberRepeat {
  columns : Int32
  rows : Int32
  dx : Double
  dy : Double
  features : Array[GerberFeature]
  mut cost : Int32
}

///|
fn translate_point(point : Point, offset : Point) -> Point {
  { x: point.x + offset.x, y: point.y + offset.y, }
}

///|
fn GerberBounds::translated(
  self : GerberBounds,
  offset : Point,
) -> GerberBounds {
  {
    lower: translate_point(self.lower, offset),
    upper: translate_point(self.upper, offset),
  }
}

///|
fn GerberKind::translated(self : GerberKind, offset : Point) -> GerberKind {
  match self {
    Flash(shape, point) => Flash(shape, translate_point(point, offset))
    Draw(shape, from, to) =>
      Draw(shape, translate_point(from, offset), translate_point(to, offset))
    Arc(arc) => Arc({ ..arc, center: translate_point(arc.center, offset), })
    Region(region) =>
      Region({
        contours: region.contours.map(contour => {
          points: contour.points.map(p => translate_point(p, offset)),
          error: contour.error,
          bounds: contour.bounds.translated(offset),
        }),
        bounds: region.bounds.translated(offset),
      })
  }
}

///|
fn GerberState::emit(
  self : GerberState,
  feature : GerberFeature,
  source : String,
) -> Unit raise GerberError {
  match self.repeat {
    None => self.features.push(feature)
    Some(repeat) => {
      let mut cost = 1
      if feature.kind is Region(region) {
        for contour in region.contours {
          cost += contour.points.length()
        }
      }
      repeat.cost += cost
      if repeat.cost > self.repeat_budget / (repeat.columns * repeat.rows) {
        raise InvalidGerber(
          source, "SR 展开超出 200000 个对象及轮廓顶点的累计上限",
        )
      }
      repeat.features.push(feature)
    }
  }
}

///|
fn parse_repeat(
  state : GerberState,
  fields : Array[Char],
  statement : String,
  source : String,
) -> Unit raise GerberError {
  if fields.is_empty() {
    guard state.repeat is Some(repeat) else {
      raise InvalidGerber(source, "SR 结束指令前没有打开步进重复")
    }
    let copies = repeat.columns * repeat.rows
    state.repeat_budget -= repeat.cost * copies
    if !repeat.features.is_empty() {
      for x in 0..<repeat.columns {
        for y in 0..<repeat.rows {
          let offset : Point = {
            x: x.to_double() * repeat.dx,
            y: y.to_double() * repeat.dy,
          }
          for item in repeat.features {
            let kind = if x == 0 && y == 0 {
              item.kind
            } else {
              item.kind.translated(offset)
            }
            if gerber_object_bounds(kind) is Some(bounds) &&
              (bounds.upper.x.is_inf() || bounds.upper.y.is_inf()) {
              raise InvalidGerber(
                source, "SR 平移后的几何坐标超出范围",
              )
            }
            if copies > 1 &&
              item.dark &&
              kind is Flash(_, _) &&
              item.refdes is Some(refdes) {
              state.repeated_refs[designator(refdes)] = true
            }
            state.features.push({ ..item, kind, })
          }
        }
      }
    }
    state.repeat = None
    state.current = None
    return
  }
  if state.repeat is Some(_) {
    raise InvalidGerber(
      source, "SR 必须显式关闭后才能开始另一组重复",
    )
  }
  guard gerber_words(fields)
    is [
      { letter: 'X', value: xs, },
      { letter: 'Y', value: ys, },
      { letter: 'I', value: dx, },
      { letter: 'J', value: dy, },
    ] else {
    raise InvalidGerber(source, "无效的 SR 参数：\{statement}")
  }
  let columns = parse_code({ letter: 'X', value: xs, }, source)
  let rows = parse_code({ letter: 'Y', value: ys, }, source)
  if columns < 1 || rows < 1 || columns > 10000 / rows {
    raise InvalidGerber(
      source, "SR 重复次数必须为正，且每组最多 10000 个单元",
    )
  }
  guard state.scale is Some(unit) else {
    raise InvalidGerber(source, "SR 前缺少 MO 单位声明")
  }
  let dx = aperture_number(dx, source) * unit
  let dy = aperture_number(dy, source) * unit
  if dx < 0.0 ||
    dy < 0.0 ||
    (dx * columns.to_double()).is_inf() ||
    (dy * rows.to_double()).is_inf() {
    raise InvalidGerber(
      source, "SR 步长必须非负，且平移量必须可计算",
    )
  }
  state.repeat = Some({ columns, rows, dx, dy, features: [], cost: 0, })
}
