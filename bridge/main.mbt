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
priv struct BrowserAudit {
  result : @mp.AuditResult
  baseline : @mp.PlacementTable
  receipt_inputs : Array[@mp.ReceiptInput]?
  build_sha256 : String
}

///|
let current_audit : Ref[BrowserAudit?] = Ref(None)

///|
fn preview_summary(report : Json, receipt_available : Bool) -> Json {
  guard report is Object(fields) else {
    abort("audit report must be an object")
  }
  let differences = fields["differences"]
  let pads = fields["pad_differences"]
  guard differences is Array(table_items) && pads is Array(pad_items) else {
    abort("audit findings must be arrays")
  }
  let mut worst : Json = Json(null)
  let mut largest = -1.0
  for item in pad_items {
    if item
      is {
        "kind": String("pad_offset"),
        "ref": String(refdes),
        "distance_mm": Number(distance, ..),
        ..
      } &&
      distance > largest {
      largest = distance
      let label = if refdes.length() > 80 {
        refdes.clamped_view(end=80).to_owned() + "…"
      } else {
        refdes
      }
      worst = { "ref": Json(label), "distance_mm": Json(distance) }
    }
  }
  let failed : Array[Json] = []
  if fields.get("pad_layers") is Some(Array(layers)) {
    for layer in layers {
      if layer is { "status": String("failed"), "side": String(side), .. } {
        failed.push(Json(side))
      }
    }
  }
  {
    "status": fields["status"],
    "reason": fields["reason"],
    "table_count": Json(table_items.length()),
    "pad_count": Json(pad_items.length()),
    "pad_checked": fields["pad_checked"],
    "worst_pad": worst,
    "failed_layers": Json(failed),
    "receipt_available": Json(receipt_available),
  }
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
  current_audit.val = None
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
    let receipt_inputs = if fingerprint_json.is_empty() {
      None
    } else {
      let inputs = decode_fingerprints(fingerprint_json)
      let expected = if has_bottom { 5 } else if has_top { 4 } else { 3 }
      if inputs.length() == expected {
        Some(inputs)
      } else {
        None
      }
    }
    current_audit.val = Some({ result, baseline, receipt_inputs, build_sha256, })
    {
      "summary": preview_summary(result.report, receipt_inputs is Some(_)),
      "html": Json(@mp.render_html_preview(result.report, baseline)),
    }
  } catch {
    @mp.InvalidInput(field, message) =>
      { "report": @mp.input_error_report(field, message) }
  }
  response.stringify()
}

///|
#export_name("export_audit")
pub fn export_audit(format : String) -> String {
  guard current_audit.val is Some(audit) else { return "" }
  match format {
    "json" => audit.result.report.stringify(indent=2) + "\n"
    "html" => @mp.render_html(audit.result.report, audit.baseline)
    "receipt" =>
      match audit.receipt_inputs {
        Some(inputs) =>
          @mp.audit_receipt(
            audit.result,
            inputs,
            host="web",
            build_sha256=audit.build_sha256,
          ).stringify(indent=2) +
          "\n"
        None => ""
      }
    _ => ""
  }
}
