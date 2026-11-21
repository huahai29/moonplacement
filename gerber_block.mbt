///|
priv struct GerberBlock {
  code : Int32
  features : Array[GerberFeature]
}

///|
fn GerberKind::block_transform(
  self : GerberKind,
  matrix : Transform2D,
  target : Point,
) -> GerberKind {
  let at = (p : Point) => translate_point(matrix.apply(p), target)
  match self {
    Flash(shape, p) => Flash(transform_shape(shape, matrix), at(p))
    Draw(shape, a, b) => Draw(transform_shape(shape, matrix), at(a), at(b))
    Arc(arc) => {
      let scale = matrix.scale()
      Arc({
        center: at(arc.center),
        start_vector: matrix.apply(arc.start_vector),
        end_vector: matrix.apply(arc.end_vector),
        clockwise: arc.clockwise != (matrix.determinant() < 0.0),
        sweep: arc.sweep,
        radius: arc.radius * scale,
        deviation: arc.deviation * scale,
        stroke_radius: arc.stroke_radius * scale,
      })
    }
    Region(region) => {
      let contours = region.contours.map(contour => {
        let points = contour.points.map(at)
        let error = contour.error * matrix.scale()
        let mut bounds = bounds_at(points[0], error)
        for p in points {
          bounds = bounds.union(bounds_at(p, error))
        }
        { points, error, bounds, }
      })
      let mut bounds = contours[0].bounds
      for contour in contours {
        bounds = bounds.union(contour.bounds)
      }
      Region({ contours, bounds, })
    }
  }
}

///|
fn parse_block(
  state : GerberState,
  rest : String,
  source : String,
) -> Unit raise GerberError {
  if rest.is_empty() {
    guard state.block_stack.pop() is Some(block) else {
      raise InvalidGerber(source, "AB 结束指令前没有打开块光圈")
    }
    state.blocks[block.code] = block.features
    state.current = None
  } else {
    guard rest.has_prefix("D") else {
      raise InvalidGerber(source, "无效的块光圈指令 AB\{rest}")
    }
    let code = parse_code(
      { letter: 'D', value: chars_to_string(to_chars(rest), 1), },
      source,
    )
    if code < 10 ||
      state.apertures.contains(code) ||
      state.blocks.contains(code) ||
      state.block_stack.any(block => block.code == code) {
      raise InvalidGerber(source, "块光圈编号无效或重复：D\{code}")
    }
    if state.block_stack.length() >= 32 {
      raise InvalidGerber(source, "AB 块光圈定义嵌套超过 32 层")
    }
    state.block_stack.push({ code, features: [], })
  }
}

///|
fn feature_cost(feature : GerberFeature) -> Int32 {
  let mut cost = 1
  if feature.kind is Region(region) {
    for contour in region.contours {
      cost += contour.points.length()
    }
  }
  cost
}

///|
fn GerberState::charge_block(
  state : GerberState,
  feature : GerberFeature,
  source : String,
) -> Unit raise GerberError {
  state.block_budget -= feature_cost(feature)
  if state.block_budget < 0 {
    raise InvalidGerber(
      source, "AB 块光圈超过 200000 个对象及轮廓顶点的累计上限",
    )
  }
}

///|
fn flash_block(
  state : GerberState,
  contents : Array[GerberFeature],
  target : Point,
  source : String,
) -> Unit raise GerberError {
  let matrix = aperture_matrix(state)
  let seen_here : Map[String, Bool] = Map([])
  let track = state.block_stack.is_empty()
  let instance = if track {
    state.block_instances += 1
    Some(state.block_instances)
  } else {
    None
  }
  for item in contents {
    if track {
      state.charge_block(item, source)
    }
    let kind = item.kind.block_transform(matrix, target)
    match kind {
      Flash(shape, _) | Draw(shape, _, _) => {
        let area = shape.area()
        if area.is_nan() || area.is_inf() {
          raise InvalidGerber(source, "AB 变换后的几何面积超出范围")
        }
      }
      _ => ()
    }
    if gerber_object_bounds(kind) is Some(bounds) && !bounds.finite() {
      raise InvalidGerber(source, "AB 变换后的几何坐标超出范围")
    }
    let dark = item.dark == state.dark
    let refdes = match item.refdes {
      None if contents.length() == 1 && kind is Flash(_, _) =>
        feature_refdes(state)
      other => other
    }
    if track && dark && kind is Flash(_, _) && refdes is Some(refdes) {
      let key = designator(refdes)
      if state.block_seen_refs.contains(key) {
        state.repeated_refs[key] = true
      }
      seen_here[key] = true
    }
    state.emit({ kind, dark, refdes, block_instance: instance, }, source)
  }
  for key, _ in seen_here {
    state.block_seen_refs[key] = true
  }
}

///|
fn GerberBounds::finite(self : GerberBounds) -> Bool {
  fn finite(value : Double) -> Bool {
    !value.is_nan() && !value.is_inf()
  }
  finite(self.lower.x) &&
  finite(self.lower.y) &&
  finite(self.upper.x) &&
  finite(self.upper.y)
}
