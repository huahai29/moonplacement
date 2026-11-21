///|
extern "js" fn input(index : Int32) -> String = "(index) => process.getBuiltinModule('node:fs').readFileSync(process.argv[2 + index], 'utf8')"

///|
extern "js" fn now() -> Double = "() => performance.now()"

///|
extern "js" fn rss() -> Int32 = "() => process.resourceUsage().maxRSS"

///|
extern "js" fn warmup_gc() -> Unit = "() => { if (globalThis.gc) globalThis.gc(); }"

///|
fn main {
  let table = @mp.read_placements(input(0), source="placements") catch {
    _ => abort("failed to read benchmark placements")
  }
  let policy = @mp.read_policy(input(1)) catch {
    _ => abort("failed to read benchmark policy")
  }
  let gerber = input(2)
  let mode = input(3)
  warmup_gc()
  let start = now()
  let parsed_document = Ok(
    if mode == "panel-direct" {
      @mp.parse_gerber_cell(gerber, row=1, column=1, source="benchmark")
    } else {
      @mp.parse_gerber(gerber, source="benchmark")
    },
  ) catch {
    @mp.InvalidGerber(_, message) => Err(message)
  }
  guard parsed_document is Ok(document) else {
    guard parsed_document is Err(message) else {
      abort("unexpected parse result")
    }
    let error : Json = {
      "parse_ms": Json(now() - start),
      "peak_kib": Json(rss()),
      "report": { "status": Json("input_error"), "message": Json(message) },
    }
    println(error.stringify())
    return
  }
  let parsed = now()
  let selected = if mode == "panel" {
    // Use the first cell; its expected references and coordinates are the same
    // at all panel sizes.
    @mp.select_panel_cell(document, row=1, column=1, source="benchmark") catch {
      @mp.InvalidGerber(_, message) => abort(message)
    }
  } else {
    document
  }
  let chosen = now()
  let result = @mp.audit(table, table, policy, top_gerber=Some(selected))
  let audited = now()
  let row : Json = {
    "features": Json(document.features.length()),
    "selected_features": Json(selected.features.length()),
    "parse_ms": Json(parsed - start),
    "select_ms": Json(chosen - parsed),
    "ready_ms": Json(chosen - start),
    "audit_ms": Json(audited - chosen),
    "peak_kib": Json(rss()),
    "report": result.report,
  }
  println(row.stringify())
}
