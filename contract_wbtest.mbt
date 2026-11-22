///|
test "report contract exposes the version, exits and UTF-8 budgets" {
  let contract = report_contract()
  guard! contract
    is {
      "x-moonplacement-exit-codes": {
        "pass": Number(0, ..),
        "different": Number(1, ..),
        "indeterminate": Number(2, ..),
        "input_error": Number(64, ..),
        ..
      },
      "x-moonplacement-input-bytes": {
        "placement": Number(8388608, ..),
        "policy": Number(65536, ..),
        ..
      },
      ..
    }
  guard! input_error_report("test.csv", "bad input")
    is {
      "schema_version": Number(3, ..),
      "status": String("input_error"),
      "field": String("test.csv"),
      "message": String("bad input"),
      ..
    }
}
