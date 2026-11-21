///|
fn block_fixture(body : String) -> String {
  "%FSLAX46Y46*%%MOMM*%%ADD10C,1*%%ADD11C,0.4*%" + body + "M02*"
}

///|
test "nested block definitions preserve order, transforms and internal references" {
  let doc = parse_gerber(
    block_fixture(
      "%ABD20*%%ABD21*%%TO.P,U3,1*%D10*X1000000Y0D03*%AB*%" +
      "%TD*%D21*X0Y2000000D03*%AB*%" +
      "%LMX*%%LR90*%%LS2*%D20*X10000000Y20000000D03*",
    ),
    source="nested",
  )
  guard! gerber_pads(doc) is [pad]
  assert_eq(pad.refdes, Some("U3"))
  assert_true((pad.center.x - 6.0).abs() < 1.0e-12)
  assert_true((pad.center.y - 18.0).abs() < 1.0e-12)
  assert_true((pad.area - @math.PI).abs() < 1.0e-12)
  assert_false(copper_at(doc, { x: 1.0, y: 0.0, }, 0.0))
  assert_true(copper_at(doc, { x: 6.8, y: 18.0, }, 0.0))
}

///|
test "positive block clears outside copper, and negative flash toggles each nested member" {
  let body = "%ABD20*%%ABD21*%%LPD*%D11*X0Y0D03*%LPC*%X2000000D03*%AB*%" +
    "%LPD*%D21*X0Y0D03*%AB*%D11*X12000000Y0D03*X20000000Y0D03*" +
    "D20*X10000000Y0D03*%LPC*%X20000000Y0D03*"
  let doc = parse_gerber(block_fixture(body), source="polarity")
  assert_true(copper_at(doc, { x: 10.0, y: 0.0, }, 0.0))
  assert_false(copper_at(doc, { x: 12.0, y: 0.0, }, 0.0))
  assert_false(copper_at(doc, { x: 20.0, y: 0.0, }, 0.0))
  assert_true(copper_at(doc, { x: 22.0, y: 0.0, }, 0.0))
}

///|
test "transformed block arcs and regions keep their geometry" {
  let doc = parse_gerber(
    block_fixture(
      "%ABD20*%%LPD*%D11*G75*G03*X1000000Y0D02*X0Y1000000I-1000000J0D01*G01*" +
      "G36*X0Y2000000D02*X1000000D01*Y3000000D01*X0D01*Y2000000D01*G37*%AB*%" +
      "%LMX*%%LR90*%%LS2*%D20*X10000000Y10000000D03*",
    ),
    source="curves",
  )
  assert_true(copper_at(doc, { x: 8.58578644, y: 8.58578644, }, 0.0))
  assert_false(copper_at(doc, { x: 11.41421356, y: 8.58578644, }, 0.0))
  assert_true(copper_at(doc, { x: 5.0, y: 9.0, }, 0.0))
  assert_false(copper_at(doc, { x: 5.0, y: 11.0, }, 0.0))
}

///|
test "block syntax rejects missing closes, collisions and undefined references" {
  for
    (body, reason) in [
      ("%AB*%", "没有打开"),
      ("%ABD20*%", "缺少结束"),
      ("%ABD10*%", "无效或重复"),
      ("%ABD20*%%ADD20C,1*%%AB*%", "已用于 AB"),
      ("%ABD20*%D20*X0Y0D03*%AB*%", "未选择光圈"),
      ("%ABD20*%%SRX2Y1I2J0*%", "不能使用 SR"),
      ("%ABD20*%D10*X0Y0D03*%AB*%D20*X1000000D03*", "当前位置"),
      ("%ABD20*%%AB*%D20*X0Y0D02*X1000000D01*", "不能用于 D01"),
    ] {
    let result = Ok(parse_gerber(block_fixture(body), source="bad AB")) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("bad AB", detail))
    assert_true(detail.contains(reason))
  }
}
