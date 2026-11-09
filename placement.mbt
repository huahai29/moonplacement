///|
priv enum Side {
  Top
  Bottom
} derive(Eq)

///|
priv struct Point {
  x : Double
  y : Double
}

///|
priv struct Placement {
  refdes : String
  xy : Point
  angle_deg : Double
  side : Side
}

///|
pub struct PlacementTable {
  priv rows : Map[String, Placement]
}

///|
priv enum Column {
  Ref
  X
  Y
  Angle
  Layer
} derive(Eq, Hash)

///|
fn column(name : String) -> Column? {
  match name.trim().to_owned().to_lower() {
    "ref" | "designator" => Some(Ref)
    "posx" | "mid x" => Some(X)
    "posy" | "mid y" => Some(Y)
    "rot" | "rotation" => Some(Angle)
    "side" | "layer" => Some(Layer)
    _ => None
  }
}

///|
fn placement_columns(
  row : CsvRow,
  source : String,
) -> Map[Column, Int32] raise InputError {
  let columns : Map[Column, Int32] = Map([])
  for index, name in row.fields {
    if column(name) is Some(kind) {
      if columns.contains(kind) {
        raise InvalidInput(
          source,
          "第 \{row.line} 行的关键列重复：\{name}",
        )
      }
      columns[kind] = index
    }
  }
  if columns.length() != 5 {
    raise InvalidInput(
      source, "表头必须包含位号、X、Y、角度和板面",
    )
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
    "top" | "front" | "f.cu" => Top
    "bottom" | "back" | "b.cu" => Bottom
    _ => raise InvalidInput(where_, "未知板面：\{raw}")
  }
}

///|
/// Read KiCad or JLC-style placement CSV. Coordinates and angles are as exported.
pub fn read_placements(
  input : String,
  source~ : String,
) -> PlacementTable raise InputError {
  let rows = parse_csv(input, source)
  if rows.length() < 2 {
    raise InvalidInput(source, "需要表头和至少一个器件")
  }
  let columns = placement_columns(rows[0], source)
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
    placements[refdes] = { refdes, xy, angle_deg, side, }
  }
  { rows: placements, }
}
