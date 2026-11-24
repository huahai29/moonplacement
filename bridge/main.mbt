///|
fn read_layer(
  text : String,
  source : String,
  row : Int32,
  column : Int32,
  reference? : @mp.GerberDocument,
) -> @mp.GerberDocument? raise @mp.InputError {
  if source.is_empty() {
    return None
  }
  let document = try {
    if row == 0 {
      @mp.parse_gerber(text, source~)
    } else {
      @mp.parse_gerber_cell(text, source~, row~, column~, reference?)
    }
  } catch {
    @mp.InvalidGerber(field, message) => raise @mp.InvalidInput(field, message)
  }
  Some(document)
}

///|
/// Browser adapter for the same public library routines used by the CLI.
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
) -> String {
  let response : Json = try {
    if top_file.is_empty() && (!bottom_file.is_empty() || row != 0) {
      raise @mp.InvalidInput("top", "请选择顶层 Gerber 铜层")
    }
    let policy = @mp.read_policy(policy_json)
    let baseline = @mp.read_placements(baseline_csv, source=baseline_file)
    let delivery = @mp.read_placements(delivery_csv, source=delivery_file)
    let top = read_layer(top_gerber, top_file, row, column)
    let bottom = read_layer(
      bottom_gerber,
      bottom_file,
      row,
      column,
      reference?=top,
    )
    let result = @mp.audit_checked(
      baseline,
      delivery,
      policy,
      top_gerber=top,
      bottom_gerber=bottom,
    )
    {
      "report": result.report,
      "html": Json(@mp.render_html(result.report, baseline)),
    }
  } catch {
    @mp.InvalidInput(field, message) =>
      { "report": @mp.input_error_report(field, message) }
  }
  response.stringify()
}

///|
fn main {

}
