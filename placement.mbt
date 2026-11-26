///|
priv enum Side {
  Top
  Bottom
} derive(Eq)

///|
/// A point in millimetres, shared by the audit pipeline and the registration
/// engine.
pub struct Point {
  x : Double
  y : Double
}

///|
/// Construct a point from millimetre coordinates.
pub fn Point::new(x : Double, y : Double) -> Point {
  { x, y, }
}

///|
priv struct Placement {
  refdes : String
  xy : Point
  angle_deg : Double
  side : Side
  value : String
  footprint : String
}

///|
pub struct PlacementTable {
  priv rows : Map[String, Placement]
  priv imported_with : TableImport
  priv coordinate_headers : (String, String)
}

///|
priv enum Column {
  Ref
  X
  Y
  Angle
  Layer
  Value
  Package
} derive(Eq, Hash)

///|
fn column(name : String, coordinates : CoordinateColumns) -> Column? {
  match name.trim().to_owned().to_lower() {
    "ref" | "designator" => Some(Ref)
    "posx" if coordinates is DefaultCoordinates => Some(X)
    "posy" if coordinates is DefaultCoordinates => Some(Y)
    "mid x" if !(coordinates is ReferenceOrigin) => Some(X)
    "mid y" if !(coordinates is ReferenceOrigin) => Some(Y)
    "ref x" if coordinates is ReferenceOrigin => Some(X)
    "ref y" if coordinates is ReferenceOrigin => Some(Y)
    "rot" | "rotation" => Some(Angle)
    "side" | "layer" => Some(Layer)
    "val" | "value" | "comment" => Some(Value)
    "package" | "footprint" | "pattern" => Some(Package)
    _ => None
  }
}

///|
fn placement_columns(
  row : CsvRow,
  source : String,
  coordinates : CoordinateColumns,
) -> Map[Column, Int32] raise InputError {
  let columns : Map[Column, Int32] = Map([])
  for index, name in row.fields {
    if column(name, coordinates) is Some(kind) {
      if columns.contains(kind) {
        raise InvalidInput(
          source,
          "第 \{row.line} 行的关键列重复：\{name}",
        )
      }
      columns[kind] = index
    }
  }
  let coordinate_error = match coordinates {
    DefaultCoordinates => "表头必须包含位号、X、Y、角度和板面"
    Midpoint => "所选坐标口径要求 Mid X 和 Mid Y 两列"
    ReferenceOrigin => "所选坐标口径要求 Ref X 和 Ref Y 两列"
  }
  if !columns.contains(X) || !columns.contains(Y) {
    raise InvalidInput(source, coordinate_error)
  }
  for required in [Ref, Angle, Layer] {
    if !columns.contains(required) {
      raise InvalidInput(
        source, "表头必须包含位号、X、Y、角度和板面",
      )
    }
  }
  columns
}

///|
fn designator(text : String) -> String {
  text.trim().to_owned().to_upper()
}

///|
fn angle_wrap(angle : Double) -> Double {
  angle - 360.0 * @math.floor((angle + 180.0) / 360.0)
}

///|
fn read_number(
  raw : String,
  max_abs : Double,
  field : String,
  where_ : String,
) -> Double raise InputError {
  let value = @string.parse_double(raw.trim()) catch {
    _ => raise InvalidInput(where_, "\{field} 不是有效数字")
  }
  if value.is_nan() || value.is_inf() || value.abs() > max_abs {
    raise InvalidInput(where_, "\{field} 超出允许范围 ±\{max_abs}")
  }
  value
}

///|
fn read_side(raw : String, where_ : String) -> Side raise InputError {
  match raw.trim().to_owned().to_lower() {
    "t" | "top" | "front" | "f.cu" => Top
    "b" | "bottom" | "back" | "b.cu" => Bottom
    _ => raise InvalidInput(where_, "未知板面：\{raw}")
  }
}

///|
/// Read KiCad or JLC-style placement CSV. Coordinates and angles are as exported.
pub fn read_placements(
  input : String,
  source~ : String,
) -> PlacementTable raise InputError {
  read_placement_table(input, source, default_table_import(), allow_empty=false)
}

///|
/// Read both original CSVs with the same policy that will drive the audit.
pub fn read_placement_pair(
  baseline : String,
  delivery : String,
  policy : Policy,
  baseline_source~ : String,
  delivery_source~ : String,
) -> (PlacementTable, PlacementTable) raise InputError {
  match policy.placement_import {
    Some(profile) => {
      let allow_empty = profile.scope is Expected(_)
      (
        read_placement_table(
          baseline,
          baseline_source,
          profile.baseline,
          allow_empty~,
        ),
        read_placement_table(
          delivery,
          delivery_source,
          profile.delivery,
          allow_empty~,
        ),
      )
    }
    None =>
      (
        read_placements(baseline, source=baseline_source),
        read_placements(delivery, source=delivery_source),
      )
  }
}

///|
fn read_placement_table(
  input : String,
  source : String,
  settings : TableImport,
  allow_empty~ : Bool,
) -> PlacementTable raise InputError {
  let rows = parse_csv(input, source)
  if rows.is_empty() || (rows.length() < 2 && !allow_empty) {
    raise InvalidInput(source, "需要表头和至少一个器件")
  }
  let columns = placement_columns(rows[0], source, settings.coordinates)
  let placements : Map[String, Placement] = Map([])
  for i in 1..<rows.length() {
    let row = rows[i]
    let where_ = "\{source} 第 \{row.line} 行"
    if row.fields.length() != rows[0].fields.length() {
      raise InvalidInput(where_, "列数与表头不一致")
    }
    let refdes = designator(row.fields[columns[Ref]])
    if refdes.is_empty() {
      raise InvalidInput(where_, "位号为空")
    }
    if placements.contains(refdes) {
      raise InvalidInput(where_, "位号重复：\{refdes}")
    }
    let xy = {
      x: read_number(row.fields[columns[X]], 1.0e6, "X", where_),
      y: read_number(row.fields[columns[Y]], 1.0e6, "Y", where_),
    }
    let angle_deg = read_number(
      row.fields[columns[Angle]],
      1.0e6,
      "角度",
      where_,
    )
    let side = read_side(row.fields[columns[Layer]], where_)
    let value = match columns.get(Value) {
      Some(index) => row.fields[index].trim().to_owned()
      None => ""
    }
    let raw_footprint = match columns.get(Package) {
      Some(index) => row.fields[index].trim().to_owned()
      None => ""
    }
    let prefix = settings.footprint_prefix
    let footprint = if !prefix.is_empty() && raw_footprint.has_prefix(prefix) {
      if raw_footprint == prefix {
        raise InvalidInput(where_, "封装库前缀后缺少封装名称")
      }
      raw_footprint[prefix.length():].to_owned()
    } else {
      raw_footprint
    }
    placements[refdes] = { refdes, xy, angle_deg, side, value, footprint, }
  }
  {
    rows: placements,
    imported_with: settings,
    coordinate_headers: (
      rows[0].fields[columns[X]].trim().to_owned(),
      rows[0].fields[columns[Y]].trim().to_owned(),
    ),
  }
}
