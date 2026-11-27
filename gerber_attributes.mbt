///|
/// X2 attribute values in file order, keyed by their exact names.
pub type GerberAttributes = @attributes.HashMap[String, Array[String]]

///|
/// Attributes of a block aperture and of its flash, outermost first on expansion.
pub struct GerberBlockAttributes {
  aperture : GerberAttributes
  object : GerberAttributes
}

///|
fn clear_gerber_attributes(state : GerberState, name : String) -> Unit {
  if name.is_empty() {
    state.aperture_attributes = @attributes.empty()
    state.object_attributes = @attributes.empty()
  } else {
    state.aperture_attributes = state.aperture_attributes.remove(name)
    state.object_attributes = state.object_attributes.remove(name)
  }
}

///|
fn parse_gerber_attribute(
  state : GerberState,
  statement : String,
  source : String,
) -> Unit raise GerberError {
  let domain = statement[:2].to_owned()
  let text = statement[2:].to_owned()
  if domain == "TD" || (domain == "TO" && text == ".D") {
    clear_gerber_attributes(state, if domain == "TD" { text } else { "" })
    return
  }
  let fields = aperture_fields(text, ',')
  guard fields is [name, .. values] && !name.is_empty() else {
    raise InvalidGerber(source, "Gerber 属性缺少名称")
  }
  let values = values.to_owned()
  match domain {
    "TF" => {
      if name == ".FileFunction" {
        parse_file_function(state, statement, source)
      }
      if name == ".FilePolarity" && values is ["Negative"] {
        raise InvalidGerber(source, "暂不支持负像铜层核验")
      }
      if state.file_attributes.get(name) is Some(previous) && previous != values {
        raise InvalidGerber(
          source,
          "Gerber 文件属性 \{name} 存在互相冲突的声明",
        )
      }
      state.file_attributes = state.file_attributes.insert(name, values)
    }
    "TA" =>
      state.aperture_attributes = state.aperture_attributes.insert(name, values)
    _ => state.object_attributes = state.object_attributes.insert(name, values)
  }
}

///|
fn attribute_owner(attributes : GerberAttributes) -> (String?, String?) {
  if attributes.get(".P") is Some([reference, .. pin_fields]) &&
    !reference.is_empty() {
    let pin = match pin_fields {
      [first, ..] if !first.is_empty() => Some(first)
      _ => None
    }
    (Some(reference), pin)
  } else if attributes.get(".C") is Some([reference, ..]) &&
    !reference.is_empty() {
    (Some(reference), None)
  } else {
    (None, None)
  }
}

///|
fn make_feature(
  state : GerberState,
  kind : GerberKind,
  aperture : GerberAttributes,
) -> GerberFeature {
  let (refdes, pin) = attribute_owner(state.object_attributes)
  {
    kind,
    dark: state.dark,
    refdes,
    pin,
    statement_number: state.statement_number,
    block_instance: None,
    aperture_attributes: aperture,
    object_attributes: state.object_attributes,
    block_attributes: [],
  }
}
