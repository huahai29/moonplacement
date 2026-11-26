///|
priv enum CoordinateColumns {
  DefaultCoordinates
  Midpoint
  ReferenceOrigin
} derive(Eq)

///|
priv struct TableImport {
  coordinates : CoordinateColumns
  footprint_prefix : String
} derive(Eq)

///|
priv enum AssemblyScope {
  All
  Expected(Map[String, Bool])
  Excluded(Map[String, Bool])
}

///|
priv struct PlacementImport {
  baseline : TableImport
  delivery : TableImport
  scope : AssemblyScope
}

///|
fn default_table_import() -> TableImport {
  { coordinates: DefaultCoordinates, footprint_prefix: "", }
}

///|
fn import_fields(
  value : Json,
  field : String,
  allowed : Array[String],
) -> Map[String, Json] raise InputError {
  guard value is Object(fields) else {
    raise InvalidInput(field, "必须是对象")
  }
  for key in fields.keys() {
    if !allowed.contains(key) {
      raise InvalidInput(field + "." + key, "未知配置项")
    }
  }
  fields
}

///|
fn table_import(value : Json?, path : String) -> TableImport raise InputError {
  guard value is Some(document) else { return default_table_import() }
  let fields = import_fields(document, path, ["coordinates", "footprint_prefix"])
  let coordinates = match fields.get("coordinates") {
    None | Some(String("auto")) => DefaultCoordinates
    Some(String("mid")) => Midpoint
    Some(String("ref")) => ReferenceOrigin
    _ => raise InvalidInput(path + ".coordinates", "使用 auto、mid 或 ref")
  }
  let footprint_prefix = match fields.get("footprint_prefix") {
    None => ""
    Some(String(prefix)) if prefix.length() > 1 &&
      prefix.has_suffix(":") &&
      prefix == prefix.trim().to_owned() => prefix
    _ =>
      raise InvalidInput(
        path + ".footprint_prefix",
        "填写以冒号结尾的库前缀，例如 antmicro-footprints:",
      )
  }
  { coordinates, footprint_prefix, }
}

///|
fn scope_refs(
  value : Json,
  field : String,
) -> Map[String, Bool] raise InputError {
  guard value is Array(entries) && !entries.is_empty() else {
    raise InvalidInput(field, "需要非空的位号列表")
  }
  let refs : Map[String, Bool] = Map([])
  for entry in entries {
    guard entry is String(text) else {
      raise InvalidInput(field, "位号必须是字符串")
    }
    let reference = designator(text)
    if reference.is_empty() || refs.contains(reference) {
      raise InvalidInput(field, "位号为空或重复：\{reference}")
    }
    refs[reference] = true
  }
  refs
}

///|
fn read_placement_import(
  document : Json,
  anchors : Array[String],
) -> PlacementImport? raise InputError {
  guard document is Object(root) && root.get("placement_import") is Some(value) else {
    return None
  }
  let fields = import_fields(value, "placement_import", [
    "baseline", "delivery", "expected_refs", "exclude_refs",
  ])
  let scope = match (fields.get("expected_refs"), fields.get("exclude_refs")) {
    (Some(_), Some(_)) =>
      raise InvalidInput(
        "placement_import", "expected_refs 与 exclude_refs 只能选一项",
      )
    (Some(refs), None) =>
      Expected(scope_refs(refs, "placement_import.expected_refs"))
    (None, Some(refs)) =>
      Excluded(scope_refs(refs, "placement_import.exclude_refs"))
    (None, None) => All
  }
  for anchor in anchors {
    if !scope.includes(anchor) {
      raise InvalidInput(
        "placement_import",
        "本次贴装范围不包含基准位号：\{anchor}",
      )
    }
  }
  Some({
    baseline: table_import(fields.get("baseline"), "placement_import.baseline"),
    delivery: table_import(fields.get("delivery"), "placement_import.delivery"),
    scope,
  })
}

///|
fn AssemblyScope::includes(self : AssemblyScope, reference : String) -> Bool {
  match self {
    All => true
    Expected(refs) => refs.contains(reference)
    Excluded(refs) => !refs.contains(reference)
  }
}

///|
fn AssemblyScope::label(self : AssemblyScope) -> String {
  match self {
    All => "all"
    Expected(_) => "expected"
    Excluded(_) => "excluded"
  }
}

///|
fn scoped_rows(
  rows : Map[String, Placement],
  scope : AssemblyScope,
) -> (Map[String, Placement], Array[String]) {
  if scope is All {
    return (rows, [])
  }
  let selected : Map[String, Placement] = Map([])
  let omitted : Array[String] = []
  for reference, row in rows {
    if scope.includes(reference) {
      selected[reference] = row
    } else {
      omitted.push(reference)
    }
  }
  omitted.sort()
  (selected, omitted)
}

///|
fn placement_import_matches(
  policy : Policy,
  baseline : PlacementTable,
  delivery : PlacementTable,
) -> Bool {
  match policy.placement_import {
    None =>
      baseline.imported_with == default_table_import() &&
      delivery.imported_with == default_table_import()
    Some(profile) =>
      baseline.imported_with == profile.baseline &&
      delivery.imported_with == profile.delivery
  }
}

///|
fn table_import_json(table : PlacementTable, omitted : Array[String]) -> Json {
  {
    "x_column": Json(table.coordinate_headers.0),
    "y_column": Json(table.coordinate_headers.1),
    "footprint_prefix": Json(table.imported_with.footprint_prefix),
    "excluded_refs": Json(omitted),
  }
}
