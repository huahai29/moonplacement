///|
fn read_layer(
  text : String,
  source : String,
  row : Int32,
  column : Int32,
) -> @mp.GerberDocument? raise @mp.InputError {
  if source.is_empty() {
    return None
  }
  let document = try {
    if row == 0 {
      @mp.parse_gerber(text, source~)
    } else {
      @mp.parse_gerber_cell(text, source~, row~, column~)
    }
  } catch {
    @mp.InvalidGerber(field, message) => raise @mp.InvalidInput(field, message)
  }
  Some(document)
}

///|
fn decode_fingerprints(text : String) -> Array[@mp.ReceiptInput] {
  let decoded = @json.parse(text) catch { _ => Json(null) }
  guard decoded is Array(entries) else { return [] }
  let inputs : Array[@mp.ReceiptInput] = []
  for entry in entries {
    guard entry
      is {
        "role": String(role),
        "bytes": Number(size, ..),
        "sha256": String(sha256),
        ..
      } else {
      return []
    }
    inputs.push({ role, byte_count: size.to_int(), sha256, })
  }
  inputs
}

///|
/// Browser adapter for the same public library routines used by the CLI.
#export_name("audit_files")
pub fn audit_files(
  baseline_csv : String,
  baseline_file : String,
  delivery_csv : String,
  delivery_file : String,
  policy_json : String,
  top_gerber : String,
  top_file : String,
  bottom_gerber : String,
  bottom_file : String,
  row : Int32,
  column : Int32,
  fingerprint_json : String,
  build_sha256 : String,
) -> String {
  let response : Json = try {
    if top_file.is_empty() && (!bottom_file.is_empty() || row != 0) {
      raise @mp.InvalidInput("top", "请选择顶层 Gerber 铜层")
    }
    let policy = @mp.read_policy(policy_json)
    let (baseline, delivery) = @mp.read_placement_pair(
      baseline_csv,
      delivery_csv,
      policy,
      baseline_source=baseline_file,
      delivery_source=delivery_file,
    )
    let has_top = !top_file.is_empty()
    let has_bottom = !bottom_file.is_empty()
    let result = if has_bottom {
      let cell = if row == 0 { None } else { Some((row, column)) }
      @mp.audit_gerber_pair(
        baseline,
        delivery,
        policy,
        top_gerber,
        bottom_gerber,
        top_source=top_file,
        bottom_source=bottom_file,
        cell?,
      )
    } else {
      let top = read_layer(top_gerber, top_file, row, column)
      @mp.audit_checked(baseline, delivery, policy, top_gerber=top)
    }
    let output : Map[String, Json] = {
      "report": result.report,
      "html": Json(@mp.render_html(result.report, baseline)),
    }
    if !fingerprint_json.is_empty() {
      let inputs = decode_fingerprints(fingerprint_json)
      let expected = if has_bottom { 5 } else if has_top { 4 } else { 3 }
      if inputs.length() == expected {
        output["receipt"] = @mp.audit_receipt(
          result,
          inputs,
          host="web",
          build_sha256~,
        )
      }
    }
    Json::object(output)
  } catch {
    @mp.InvalidInput(field, message) =>
      { "report": @mp.input_error_report(field, message) }
  }
  response.stringify()
}
