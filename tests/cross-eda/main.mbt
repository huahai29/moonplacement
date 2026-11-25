///|
extern "js" fn read_test_file(index : Int32) -> String = "(index) => process.getBuiltinModule('node:fs').readFileSync(process.argv[index + 2], 'utf8')"

///|
fn main {
  let baseline = @mp.read_placements(read_test_file(0), source="kicad") catch {
    @mp.InvalidInput(_, message) => abort(message)
  }
  let delivery = @mp.read_placements(read_test_file(1), source="easyeda") catch {
    @mp.InvalidInput(_, message) => abort(message)
  }
  let policy = @mp.read_policy(read_test_file(2)) catch {
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
