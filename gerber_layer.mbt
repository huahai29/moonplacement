///|
fn parse_file_function(
  state : GerberState,
  statement : String,
  source : String,
) -> Unit raise GerberError {
  let fields = statement.split(",").map(field => field.to_owned()).collect()
  guard fields is ["TF.FileFunction", category, ..] && !category.is_empty() else {
    raise InvalidGerber(source, "无效的 Gerber .FileFunction 声明")
  }
  if category == "Copper" {
    guard fields is [_, _, layer, side, ..] &&
      (side == "Top" || side == "Bot" || side == "Inr") &&
      (
        fields.length() == 4 ||
        fields is [_, _, _, _, "Plane" | "Signal" | "Mixed" | "Hatched"]
      ) else {
      raise InvalidGerber(
        source, "无效的 Gerber 铜层 .FileFunction 声明",
      )
    }
    let chars = to_chars(layer)
    guard chars.get(0) == Some('L') else {
      raise InvalidGerber(
        source, "Gerber .FileFunction 缺少有效的铜层编号",
      )
    }
    let number = parse_code(
      { letter: 'L', value: chars_to_string(chars, 1), },
      source,
    )
    if number == 0 || (side == "Top" && number != 1) {
      raise InvalidGerber(
        source, "Gerber .FileFunction 的铜层编号与板面不一致",
      )
    }
  }
  if state.file_function is Some(previous) && previous != statement {
    raise InvalidGerber(
      source, "Gerber .FileFunction 存在互相冲突的声明",
    )
  }
  state.file_function = Some(statement)
}

///|
priv struct LayerIssue {
  side : Side
  source : String
  message : String
}

///|
fn check_layer_slots(
  top : GerberDocument?,
  bottom : GerberDocument?,
) -> Array[LayerIssue] {
  let issues : Array[LayerIssue] = []
  for (side, layer) in [(Top, top), (Bottom, bottom)] {
    guard layer is Some(document) && document.file_function is Some(declaration) else {
      continue
    }
    let fields = declaration.split(",").map(field => field.to_owned()).collect()
    let matches = match (side, fields) {
      (Top, [_, "Copper", _, "Top", ..])
      | (Bottom, [_, "Copper", _, "Bot", ..]) => true
      _ => false
    }
    if !matches {
      let expected = if side == Top { "顶层铜" } else { "底层铜" }
      issues.push({
        side,
        source: document.source,
        message: "Gerber .FileFunction 与\{expected}输入不符：\{declaration}",
      })
    }
  }
  issues
}
