///|
fn append_policy_field(path : StringBuilder, key : String) -> Unit {
  let identifier = !key.is_empty() &&
    key
    .iter()
    .all(ch => {
      (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_'
    })
  if identifier {
    if !path.is_empty() {
      path.write_char('.')
    }
    path.write_string(key)
  } else {
    path.write_string("[" + Json(key).stringify() + "]")
  }
}

///|
fn policy_fields(
  value : Json,
  path : String,
  allowed : Array[String],
) -> Map[String, Json] raise InputError {
  guard value is Object(fields) else {
    raise InvalidInput(
      if path.is_empty() {
        "policy"
      } else {
        path
      },
      "必须是对象",
    )
  }
  for key in fields.keys() {
    if !allowed.contains(key) {
      let location = StringBuilder()
      location.write_string(path)
      append_policy_field(location, key)
      raise InvalidInput(location.to_string(), "未知配置项")
    }
  }
  fields
}

///|
/// The pinned core exposes duplicate-key details through this variant.
#warnings("-alert_visibility")
fn parse_policy_json(input : String) -> Json raise InputError {
  @json.parse(input, reject_duplicate_keys=true) catch {
    @json.DuplicateKey(at, key) =>
      raise InvalidInput(
        duplicate_policy_path(input, at, key),
        "配置项重复（第 \{at.line} 行，第 \{at.column + 1} 列）",
      )
    error => raise InvalidInput("policy", "配置无法解析：\{error}")
  }
}

///|
priv enum PolicyContainer {
  ObjectField(String?)
  ArrayItem(Int32)
}

///|
/// The core parser finds and rejects duplicate decoded keys. Walk only the
/// prefix before that token to recover its enclosing object and array path.
fn duplicate_policy_path(
  input : String,
  at : @json.Position,
  key : String,
) -> String {
  let units = input.code_units()
  let mut line_start = 0
  let mut line = 1
  while line < at.line && line_start < units.length() {
    if units[line_start] == '\n' {
      line += 1
    }
    line_start += 1
  }
  let stop = (line_start + at.column).min(units.length())
  let stack : Array[PolicyContainer] = []
  let mut i = 0
  while i < stop {
    match units[i] {
      '{' => stack.push(ObjectField(None))
      '[' => stack.push(ArrayItem(0))
      '}' | ']' => stack.pop() |> ignore
      ',' => {
        let top = stack.length() - 1
        match stack.get(top) {
          Some(ObjectField(_)) => stack[top] = ObjectField(None)
          Some(ArrayItem(index)) => stack[top] = ArrayItem(index + 1)
          None => ()
        }
      }
      '"' => {
        let start = i
        i += 1
        while i < stop && units[i] != '"' {
          i += if units[i] == '\\' { 2 } else { 1 }
        }
        let top = stack.length() - 1
        if i < stop && stack.get(top) is Some(ObjectField(None)) {
          let field = @json.parse(input[start:i + 1]) catch { _ => Json(null) }
          if field is String(name) {
            stack[top] = ObjectField(Some(name))
          }
        }
      }
      _ => ()
    }
    i += 1
  }
  let path = StringBuilder()
  for segment in stack {
    match segment {
      ObjectField(Some(name)) => append_policy_field(path, name)
      ArrayItem(index) => path.write_string("[\{index}]")
      ObjectField(None) => ()
    }
  }
  append_policy_field(path, key)
  path.to_string()
}
