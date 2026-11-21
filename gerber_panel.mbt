///|
let repeated_reference_warning = "拼板中有重复位号，请指定单元或拆分后核验"

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
    raise InvalidGerber(
      source, "按单元核对需要每个铜层恰好有一组非空、真正重复的 SR 网格",
    )
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
  let offset : Point = {
    x: (column - 1).to_double() * grid.dx,
    y: (row - 1).to_double() * grid.dy,
  }
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
  for feature in document.features {
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
