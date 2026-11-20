///|
const SAMPLE_GERBER : String = "%FSLAX46Y46*%\n%MOMM*%\n%ADD10C,0.5*%\n%ADD11R,1.0X0.6*%\n" +
  "%TO.C,R1*%\nD10*%\nX10000000Y10000000D03*%\nX11000000Y10000000D03*%\n" +
  "%TO.C,C1*%\nD11*%\nX20000000Y15000000D03*%\n%TO.D*%\nM02*\n"

///|
test "parses flashes, apertures and X2 component attributes" {
  let document = parse_gerber(SAMPLE_GERBER, source="fixture")
  assert_eq(document.features.length(), 3)
  let pads = gerber_pads(document)
  assert_eq(pads.length(), 3)
  assert_eq(pads[0].refdes, Some("R1"))
  assert_eq(pads[1].refdes, Some("R1"))
  assert_eq(pads[2].refdes, Some("C1"))
  assert_true((pads[0].center.x - 10.0).abs() < 1.0e-12)
  assert_true((pads[1].center.x - 11.0).abs() < 1.0e-12)
  assert_true((pads[2].center.y - 15.0).abs() < 1.0e-12)
  assert_true((pads[0].area - @math.PI * 0.25 * 0.25).abs() < 1.0e-12)
}

///|
test "pad check compares area-weighted copper centroids" {
  let document = parse_gerber(SAMPLE_GERBER, source="fixture")
  let ok = check_pads(
    document,
    ["R1", "C1"],
    [{ x: 10.5, y: 10.0, }, { x: 20.0, y: 15.0, }],
    0.05,
  )
  assert_eq(ok.length(), 0)
  let bad = check_pads(document, ["R1"], [{ x: 10.0, y: 10.0, }], 0.1)
  assert_eq(bad.length(), 1)
  guard! bad
    is [
      {
        "ref": String("R1"),
        "kind": String("pad_offset"),
        "distance_mm": Number(distance, ..),
        ..
      },
    ]
  assert_true((distance - 0.5).abs() < 1.0e-12)
}

///|
test "copper coverage works without X2 attributes" {
  let text = "%FSLAX46Y46*%%MOMM*%%ADD10C,1.0*%D10*X5000000Y5000000D03*"
  let document = parse_gerber(text, source="fixture")
  assert_true(copper_at(document, { x: 5.0, y: 5.0, }, 0.0))
  assert_true(!copper_at(document, { x: 9.0, y: 9.0, }, 0.0))
  let evidence = pad_evidence(
    document,
    ["U1", "U2"],
    [{ x: 9.0, y: 9.0, }, { x: 5.0, y: 5.0, }],
    0.0,
  )
  assert_true(evidence is [Unverified, CopperOnly])
}

///|
test "TO.P supplies the owner and X2 deletion respects the named attribute" {
  let text = "%FSLAX46Y46*%%MOMM*%%ADD10C,1.0*%D10*" +
    "%TO.C,legacy*%%TO.P,R1,2,pin*%%TO.N,N1*%%TD.N*%X1000000Y1000000D03*" +
    "%TD.P*%%TO.CVal,something*%X2000000Y1000000D03*" +
    "%TD*%X3000000Y1000000D03*M02*"
  let pads = gerber_pads(parse_gerber(text, source="fixture"))
  assert_eq(pads.map(pad => pad.refdes), [Some("R1"), Some("legacy"), None])
}

///|
test "clear flashes remove nearby-copper evidence" {
  let text = "%FSLAX46Y46*%%MOMM*%%ADD10C,1.0*%D10*X5000000Y5000000D03*" +
    "%LPC*%X5000000Y5000000D03*M02*"
  let document = parse_gerber(text, source="fixture")
  assert_true(!copper_at(document, { x: 5.0, y: 5.0, }, 0.0))
}

///|
test "inch units scale coordinates into millimetres" {
  let text = "%FSLAX24Y24*%%MOIN*%%ADD10C,0.04*%D10*X10000Y20000D03*"
  let document = parse_gerber(text, source="fixture")
  let pads = gerber_pads(document)
  assert_true((pads[0].center.x - 25.4).abs() < 1.0e-9)
  assert_true((pads[0].center.y - 50.8).abs() < 1.0e-9)
}

///|
test "trailing zero omission, modal axes, and flashes use the file position" {
  let text = "%FSTAX23Y23*%%MOIN*%%ADD10C,0.04*%D10*" +
    "X-015Y+02D02*G04 comment mentions G91 and D99*D03*Y003D03*" +
    "M02*X99Y99D03*"
  let pads = gerber_pads(parse_gerber(text, source="fixture"))
  assert_eq(pads.length(), 2)
  assert_true((pads[0].center.x + 38.1).abs() < 1.0e-9)
  assert_true((pads[0].center.y - 50.8).abs() < 1.0e-9)
  assert_true((pads[1].center.x + 38.1).abs() < 1.0e-9)
  assert_true((pads[1].center.y - 7.62).abs() < 1.0e-9)
}

///|
test "regions become filled polygons" {
  let text = "%FSLAX46Y46*%%MOMM*%G36*X1000000Y1000000D02*X2000000Y1000000D01*" +
    "X2000000Y2000000D01*X1000000Y2000000D01*X1000000Y1000000D01*G37*"
  let document = parse_gerber(text, source="fixture")
  assert_true(copper_at(document, { x: 1.5, y: 1.5, }, 0.0))
  assert_true(!copper_at(document, { x: 3.0, y: 1.5, }, 0.0))
}

///|
test "unsupported aperture template reports an error" {
  let result = Ok(parse_gerber("%MOMM*%%ADD10Q,1.0*%", source="fixture")) catch {
    error => Err(error)
  }
  assert_true(result is Err(InvalidGerber("fixture", _)))
}

///|
test "macro rotation, external reflection, and reset transform the aperture around its origin" {
  let text = "%FSLAX46Y46*%%MOMM*%%AMRect*21,1,4,2,$1,0,90*%" +
    "%ADD10Rect,1*%%ADD11C,1*%D10*%LMY*%%LR90*%%LS2*%" +
    "%TO.P,R1,1*%X10000000Y10000000D03*%LMN*%%LR0*%%LS1*%D11*" +
    "%TO.P,R2,1*%D03*M02*"
  let document = parse_gerber(text, source="fixture")
  let pads = gerber_pads(document)
  guard! pads is [rect, circle]
  assert_eq(rect.refdes, Some("R1"))
  assert_eq(circle.refdes, Some("R2"))
  assert_true((rect.center.x - 12.0).abs() < 1.0e-12)
  assert_true((rect.center.y - 10.0).abs() < 1.0e-12)
  assert_true((rect.area - 32.0).abs() < 1.0e-12)
  assert_true(rect.shape.contains(rect.center, { x: 15.5, y: 10.0, }))
  assert_false(rect.shape.contains(rect.center, { x: 12.0, y: 13.0, }))
  assert_eq(circle.center.x, 10.0)
  assert_eq(circle.center.y, 10.0)
}

///|
fn rounded_macro_fixture(
  circle~ : String = "1,1,$10,1,1",
  outline~ : String = "4,1,4,1,1,3,1,3,2,1,2,1,1,0",
) -> String {
  "%FSLAX46Y46*%%MOMM*%%AMRounded*$10=($1+2x$2)/2*" +
  outline +
  "*" +
  circle +
  "*1,1,$10,3,1*1,1,$10,3,2*1,1,$10,1,2*" +
  "20,1,$10,1,1,3,1,0*20,1,$10,3,1,3,2,0*" +
  "20,1,$10,3,2,1,2,0*20,1,$10,1,2,1,1,0*%" +
  "%ADD10Rounded,0.4X0.3*%D10*%LMX*%%LR90*%%LS2*%" +
  "%TO.P,U3,1*%X10000000Y10000000D03*M02*"
}

///|
test "multi-primitive rounded aperture uses union area and transformed copper center" {
  let document = parse_gerber(rounded_macro_fixture(), source="rounded")
  guard! gerber_pads(document) is [pad]
  assert_eq(pad.refdes, Some("U3"))
  assert_true((pad.center.x - 7.0).abs() < 1.0e-12)
  assert_true((pad.center.y - 6.0).abs() < 1.0e-12)
  // Transformed inner rectangle 2 by 4, plus radius-0.5 rounding.
  assert_true((pad.area - (14.0 + @math.PI * 0.25)).abs() < 1.0e-12)
  assert_true(pad.shape.contains(pad.center, { x: 5.65, y: 3.65, }))
  let cut_corner : Point = { x: 5.55, y: 3.55, }
  assert_false(pad.shape.contains(pad.center, cut_corner))
  assert_true(pad.shape.expanded(0.15).contains(pad.center, cut_corner))
}

///|
test "malformed macro expressions and unrecognized combinations are refused" {
  for
    (input, message) in [
      (rounded_macro_fixture(circle="1,0,$10,1,1"), "多图元光圈宏"),
      (rounded_macro_fixture(circle="1,1,$10,3,1"), "多图元光圈宏"),
      (rounded_macro_fixture(circle="1,1,$10/0,1,1"), "除数不能为零"),
      (rounded_macro_fixture(circle="1,1,($10,1,1"), "缺少右括号"),
      (
        rounded_macro_fixture(outline="4,1,4,1,1,3,1,3,2,1,2,0,1,0"),
        "多图元光圈宏",
      ),
    ] {
    let result = Ok(parse_gerber(input, source="rounded")) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("rounded", detail))
    assert_true(detail.contains(message))
  }
}

///|
test "macro expressions respect precedence, assignments and undefined variable defaults" {
  let variables : Map[Int32, Double] = Map([(1, 8.0)])
  macro_assign("$2=-($1+2)/2+3x2", variables, "test")
  assert_eq(macro_value("$2+$3", variables, "test"), 1.0)
  assert_eq(macro_value("$1/2/2", variables, "test"), 2.0)
  let result = Ok(macro_assign("$1=0", variables, "test")) catch {
    error => Err(error)
  }
  guard! result is Err(InvalidGerber("test", message))
  assert_true(message.contains("不能重新定义变量"))
}
