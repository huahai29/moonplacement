///|
test "receipt embeds the same report and the host's byte fingerprints" {
  let board = fixture_table(
    "R1,10,10,0,top\nR2,20,10,0,top\nR3,10,20,0,top\nD1,5,5,0,top",
  )
  let result = audit(board, board, matching_policy())
  let receipt = audit_receipt(
    result,
    [{ role: "baseline", byte_count: 42, sha256: "sample-input-digest", }],
    host="test",
    build_sha256="sample-build-digest",
  )
  guard receipt
    is {
      "schema": String("moonplacement.receipt.v1"),
      "producer": {
        "name": String("MoonPlacement"),
        "host": String("test"),
        "build_sha256": String("sample-build-digest"),
        ..
      },
      "inputs": [
        {
          "role": String("baseline"),
          "bytes": Number(size, ..),
          "sha256": String("sample-input-digest"),
          ..
        },
      ],
      "report": report,
      ..
    } else {
    fail("unexpected receipt: \{receipt.stringify()}")
  }
  assert_eq(size.to_int(), 42)
  assert_eq(report, result.report)
}
