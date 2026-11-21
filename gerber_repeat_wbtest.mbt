///|
test "SR repeats the whole block in Y-first order and preserves layer polarity" {
  let doc = parse_gerber(
    "%FSLAX46Y46*%%MOMM*%%ADD10C,0.4*%D10*X0Y0D03*" +
    "%SRX2Y2I1J2.5*%%LPD*%X1000000Y0D03*%LPC*%X0Y0D03*%SR*%M02*",
    source="overlapping panel",
  )
  assert_eq(doc.features.length(), 9)
  guard! doc.features[3].kind is Flash(_, second)
  guard! doc.features[5].kind is Flash(_, third)
  assert_eq(second.x, 1.0)
  assert_eq(second.y, 2.5)
  assert_eq(third.x, 2.0)
  assert_eq(third.y, 0.0)
  assert_false(copper_at(doc, { x: 0.0, y: 0.0, }, 0.0))
  assert_false(copper_at(doc, { x: 1.0, y: 0.0, }, 0.0))
  assert_true(copper_at(doc, { x: 2.0, y: 0.0, }, 0.0))
  assert_true(copper_at(doc, { x: 2.0, y: 2.5, }, 0.0))
}

///|
test "SR translates arcs and regions in MO units without reusing prior coordinates" {
  let doc = parse_gerber(
    "%FSLAX46Y46*%%MOIN*%%ADD10C,0.01*%D10*%SRX2Y1I0.5J0*%" +
    "G75*G03*X100000Y0D02*I-100000J0D01*" +
    "G01*G36*X-10000Y-10000D02*X10000D01*Y10000D01*X-10000D01*Y-10000D01*G37*" +
    "%SR*%M02*",
    source="inch panel",
  )
  assert_true(copper_at(doc, { x: 12.7, y: 0.0, }, 0.0))
  assert_true(copper_at(doc, { x: 15.24, y: 0.0, }, 0.0))
  assert_false(copper_at(doc, { x: 12.7, y: 1.27, }, 0.0))
}

///|
test "SR refuses malformed, unclosed and oversized blocks" {
  let block = "%SRX2Y1I1J0*%"
  let head = "%FSLAX46Y46*%%MOMM*%%ADD10C,0.4*%D10*"
  for
    (body, reason) in [
      ("%SR*%", "没有打开"),
      (block, "缺少结束"),
      (block + block, "显式关闭"),
      ("%SRX0Y2I1J1*%", "重复次数"),
      ("%SRX101Y100I1J1*%", "最多 10000"),
      ("%SRX2Y1I-1J0*%", "非负"),
      ("%SRX2I1Y1J0*%", "无效的 SR 参数"),
      (block + "X0Y0D03*%SR*%X1000000D03*", "当前位置"),
    ] {
    let result = Ok(parse_gerber(head + body + "M02*", source="bad panel")) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("bad panel", detail))
    assert_true(detail.contains(reason))
  }
  let oversized = StringBuilder()
  oversized.write_string("%SRX100Y100I1J1*%")
  for _ in 0..<21 {
    oversized.write_string("X0Y0D03*")
  }
  oversized.write_string("%SR*%M02*")
  let result = Ok(
    parse_gerber(head + oversized.to_string(), source="big panel"),
  ) catch {
    error => Err(error)
  }
  guard! result is Err(InvalidGerber("big panel", detail))
  assert_true(detail.contains("累计上限"))
}
