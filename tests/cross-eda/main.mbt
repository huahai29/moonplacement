///|
extern "js" fn read_test_file(index : Int32) -> String = "(index) => process.getBuiltinModule('node:fs').readFileSync(process.argv[index + 2], 'utf8')"

///|
fn main {
  let policy = @mp.read_policy(read_test_file(2)) catch {
    @mp.InvalidInput(_, message) => abort(message)
  }
  let (baseline, delivery) = @mp.read_placement_pair(
    read_test_file(0),
    read_test_file(1),
    policy,
    baseline_source="kicad",
    delivery_source="easyeda",
  ) catch {
    @mp.InvalidInput(_, message) => abort(message)
  }
  let bottom = @mp.parse_gerber(read_test_file(3), source="bottom copper") catch {
    @mp.InvalidGerber(_, message) => abort(message)
  }
  let result = @mp.audit_checked(
    baseline,
    delivery,
    policy,
    bottom_gerber=Some(bottom),
  ) catch {
    @mp.InvalidInput(_, message) => abort(message)
  }
  println(result.report.stringify())
}
