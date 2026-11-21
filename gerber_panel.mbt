///|
let repeated_reference_warning = "拼板中有重复位号，请指定单元或拆分后核验"

///|
let single_grid_message = "按单元核对需要每个铜层恰好有一组非空、真正重复的 SR 网格"

///|
pub struct GerberGrid {
  columns : Int32
  rows : Int32
  dx : Double
  dy : Double
  footprint : GerberBounds
}

///|
/// One-based row (positive Y) and column (positive X) of a Gerber SR grid.
pub struct PanelCell {
  row : Int32
  column : Int32
  grid : GerberGrid
  offset_mm : Point
}

///|
fn panel_grid(
  document : GerberDocument,
  source : String,
) -> GerberGrid raise GerberError {
  guard document.panel_grids is [grid] else {
    raise InvalidGerber(source, single_grid_message)
  }
  grid
}

///|
fn panel_axis(
  minimum : Double,
  maximum : Double,
  step : Double,
  count : Int32,
  index : Int32,
  source : String,
) -> (Double, Double)? raise GerberError {
  if count == 1 {
    return None
  }
  let gap = step - (maximum - minimum)
  let origin = minimum - gap * 0.5
  let low = origin + (index - 1).to_double() * step
  let high = origin + index.to_double() * step
  let offset = (index - 1).to_double() * step
  if !(gap > 0.0 && low < minimum + offset && maximum + offset < high) ||
    low.is_inf() ||
    high.is_inf() {
    raise InvalidGerber(
      source, "SR 单元的几何范围重叠、相切或无法安全分隔",
    )
  }
  Some((low, high))
}

///|
fn inside_axis(
  minimum : Double,
  maximum : Double,
  axis : (Double, Double)?,
) -> Int32 {
  match axis {
    None => 1
    Some((low, high)) if maximum < low || minimum > high => -1
    Some((low, high)) if minimum > low && maximum < high => 1
    _ => 0
  }
}

///|
/// Parse a single SR cell without expanding the whole panel. Its objects are
/// returned in the first cell's coordinate frame. For a bottom layer, pass
/// the top layer already selected at the same row and column as reference.
pub fn parse_gerber_cell(
  text : String,
  row~ : Int32,
  column~ : Int32,
  source~ : String,
  reference? : GerberDocument,
) -> GerberDocument raise GerberError {
  let (document, base) = parse_gerber_layer(text, source, keep_panel_base=true)
  select_gerber_cell(document, row, column, source, reference, base)
}

///|
/// Select one unambiguous SR cell and move it to the first cell's coordinate
/// frame. File-wide objects inside the same cell keep their original order.
/// Pass the selected top layer as reference when selecting the bottom layer.
pub fn select_panel_cell(
  document : GerberDocument,
  row~ : Int32,
  column~ : Int32,
  source~ : String,
  reference? : GerberDocument,
) -> GerberDocument raise GerberError {
  select_gerber_cell(document, row, column, source, reference, None)
}

///|
fn select_gerber_cell(
  document : GerberDocument,
  row : Int32,
  column : Int32,
  source : String,
  reference : GerberDocument?,
  base : (Int32, Int32)?,
) -> GerberDocument raise GerberError {
  if document.panel_cell is Some(_) {
    raise InvalidGerber(source, "该铜层已经选定拼板单元")
  }
  let own = panel_grid(document, source)
  let grid = match reference {
    Some(top) => {
      guard top.panel_cell is Some(cell) &&
        cell.row == row &&
        cell.column == column else {
        raise InvalidGerber(
          source, "参考铜层必须已选中相同的拼板单元",
        )
      }
      cell.grid
    }
    None => own
  }
  if own.rows != grid.rows ||
    own.columns != grid.columns ||
    (grid.columns > 1 && own.dx != grid.dx) ||
    (grid.rows > 1 && own.dy != grid.dy) {
    raise InvalidGerber(
      source, "顶层与底层 SR 网格的行列或步长不一致",
    )
  }
  if row < 1 || row > grid.rows || column < 1 || column > grid.columns {
    raise InvalidGerber(
      source,
      "拼板单元超出范围：须选择第 1–\{grid.rows} 行、第 1–\{grid.columns} 列",
    )
  }
  let x = panel_axis(
    grid.footprint.lower.x,
    grid.footprint.upper.x,
    grid.dx,
    grid.columns,
    column,
    source,
  )
  let y = panel_axis(
    grid.footprint.lower.y,
    grid.footprint.upper.y,
    grid.dy,
    grid.rows,
    row,
    source,
  )
  let offset = repeat_offset(grid.dx, grid.dy, column, row)
  let projected = own.footprint.translated(offset)
  if inside_axis(projected.lower.x, projected.upper.x, x) != 1 ||
    inside_axis(projected.lower.y, projected.upper.y, y) != 1 {
    raise InvalidGerber(
      source, "铜层网格原点或范围不一致，不能唯一选定单元",
    )
  }
  let repeated_refs : Map[String, Bool] = Map([])
  let block_owners : Map[String, Int32] = Map([])
  let features : Array[GerberFeature] = []
  let inverse : Point = { x: -offset.x, y: -offset.y, }
  let neighbors : Array[Point] = []
  if base is Some(_) {
    // Translation is monotone along each axis. Once the four nearest
    // neighbors are outside, all further copies are outside as well.
    if column > 1 {
      neighbors.push(repeat_offset(own.dx, own.dy, column - 1, row))
    }
    if column < own.columns {
      neighbors.push(repeat_offset(own.dx, own.dy, column + 1, row))
    }
    if row > 1 {
      neighbors.push(repeat_offset(own.dx, own.dy, column, row - 1))
    }
    if row < own.rows {
      neighbors.push(repeat_offset(own.dx, own.dy, column, row + 1))
    }
  }
  let last = repeat_offset(own.dx, own.dy, own.columns, own.rows)
  for index, original in document.features {
    let feature = if base is Some((start, end)) && index >= start && index < end {
      if repeat_bounds_at(original.kind, last) is Some(bounds) &&
        !bounds.finite() {
        raise InvalidGerber(source, "SR 平移后的几何坐标超出范围")
      }
      for neighbor in neighbors {
        if repeat_bounds_at(original.kind, neighbor) is Some(bounds) &&
          inside_axis(bounds.lower.x, bounds.upper.x, x) != -1 &&
          inside_axis(bounds.lower.y, bounds.upper.y, y) != -1 {
          raise InvalidGerber(
            source, "铜层对象跨越拼板单元边界，无法安全选定该单元",
          )
        }
      }
      if row == 1 && column == 1 {
        original
      } else {
        { ..original, kind: original.kind.translated(offset), }
      }
    } else {
      original
    }
    guard gerber_object_bounds(feature.kind) is Some(bounds) else { continue }
    let px = inside_axis(bounds.lower.x, bounds.upper.x, x)
    let py = inside_axis(bounds.lower.y, bounds.upper.y, y)
    if px == -1 || py == -1 {
      continue
    }
    if px == 0 || py == 0 {
      raise InvalidGerber(
        source, "铜层对象跨越拼板单元边界，无法安全选定该单元",
      )
    }
    if feature.dark &&
      feature.kind is Flash(_, _) &&
      feature.block_instance is Some(instance) &&
      feature.refdes is Some(refdes) {
      let key = designator(refdes)
      if block_owners.get(key) is Some(other) && instance != other {
        repeated_refs[key] = true
      }
      block_owners[key] = instance
    }
    features.push({ ..feature, kind: feature.kind.translated(inverse), })
  }
  let warnings = document.warnings.filter(warning => {
    warning != repeated_reference_warning
  })
  if !repeated_refs.is_empty() {
    warnings.push(repeated_reference_warning)
  }
  {
    ..document,
    features,
    repeated_refs,
    warnings,
    panel_cell: Some({ row, column, grid, offset_mm: offset, }),
  }
}
