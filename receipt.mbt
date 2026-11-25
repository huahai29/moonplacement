///|
/// Digest of the original bytes the host used for one audit input.
pub(all) struct ReceiptInput {
  role : String
  byte_count : Int32
  sha256 : String
}

///|
/// Wrap a completed audit with byte fingerprints supplied by its host.
pub fn audit_receipt(
  result : AuditResult,
  inputs : Array[ReceiptInput],
  host~ : String,
  build_sha256~ : String,
) -> Json {
  let records : Array[Json] = inputs.map(input => {
    "role": Json(input.role),
    "bytes": Json(input.byte_count),
    "sha256": Json(input.sha256),
  })
  {
    "schema": Json("moonplacement.receipt.v1"),
    "producer": {
      "name": Json("MoonPlacement"),
      "package_version": Json("0.2.0"),
      "host": Json(host),
      "build_sha256": Json(build_sha256),
    },
    "inputs": Json(records),
    "report": result.report,
  }
}
