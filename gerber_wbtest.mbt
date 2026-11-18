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
