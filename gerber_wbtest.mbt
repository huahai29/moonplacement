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
test "region cut-in keeps a circular hole while separate contours add copper" {
  let outside = "%FSLAX46Y46*%%MOMM*%G75*G36*X4000000Y0D02*X4000000Y3000000D01*" +
    "X-4000000Y3000000D01*X-4000000Y-3000000D01*X4000000Y-3000000D01*X4000000Y0D01*" +
    "X1000000Y0D01*G02*I-1000000J0D01*G01*X4000000Y0D01*"
  let alone = parse_gerber(outside + "G37*M02*", source="arc cut-in")
  assert_false(copper_at(alone, { x: 0.0, y: 0.0, }, 0.0))
  assert_true(copper_at(alone, { x: 0.8, y: 0.8, }, 0.0))
  assert_false(copper_at(alone, { x: 0.6, y: 0.6, }, 0.0))
  assert_true(copper_at(alone, { x: 0.5, y: 1.0, }, 0.0))
  let circles = "X500000Y0D02*G03*I-500000J0D01*G01*"
  let union = parse_gerber(outside + circles + "G37*M02*", source="arc cut-in")
  assert_true(copper_at(union, { x: 0.0, y: 0.0, }, 0.0))
  assert_false(copper_at(union, { x: 0.7, y: 0.0, }, 0.0))
  let clear_then_repaint = parse_gerber(
    outside.replace(old="G36*", new="%LPC*%G36*") +
    "G37*%LPD*%" +
    "G36*X500000Y0D02*G03*I-500000J0D01*G37*M02*",
    source="repaint after clearance",
  )
  assert_true(copper_at(clear_then_repaint, { x: 0.0, y: 0.0, }, 0.0))
  assert_false(copper_at(clear_then_repaint, { x: 0.8, y: 0.8, }, 0.0))
}

///|
test "regions reject a broken outline and missing D02 or G36" {
  for
    (commands, reason) in [
      (
        "G36*X0Y0D02*X1000000Y0D01*X1000000Y1000000D01*X0Y1000000D01*G37*", "闭合",
      ),
      ("X0Y0D02*G36*X1000000Y1000000D01*G37*", "D02"),
      ("G37*", "G36"),
      ("G36*%LPC*%G37*", "极性"),
    ] {
    let result = Ok(
      parse_gerber("%FSLAX46Y46*%%MOMM*%" + commands, source="invalid region"),
    ) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("invalid region", detail))
    assert_true(detail.contains(reason))
  }
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

///|
test "standard apertures subtract a concentric round hole for each template" {
  for
    (template, outside_area) in [
      ("C,4X1", 4.0 * @math.PI),
      ("R,4X3X1", 12.0),
      ("O,4X3X1", 3.0 + 2.25 * @math.PI),
      ("P,4X4X30X1", 8.0),
    ] {
    let document = parse_gerber(
      "%FSLAX46Y46*%%MOMM*%%ADD10" +
      template +
      "*%D10*%LS2*%X1000000Y2000000D03*M02*",
      source="standard holes",
    )
    guard! gerber_pads(document) is [pad]
    assert_true((pad.area - (4.0 * outside_area - @math.PI)).abs() < 1.0e-12)
    assert_eq(pad.center.x, 1.0)
    assert_eq(pad.center.y, 2.0)
    assert_false(copper_at(document, pad.center, 0.1))
    assert_true(copper_at(document, { x: 1.95, y: 2.0, }, 0.1))
    assert_true(copper_at(document, { x: 2.1, y: 2.0, }, 0.0))
  }
}

///|
test "off-center clearance changes copper centroid and follows aperture transforms" {
  let document = parse_gerber(
    "%FSLAX46Y46*%%MOMM*%%AMWindow*21,1,4,3,1,0,90*1,0,1,1.5,0,90*%" +
    "%ADD10Window*%D10*%LMX*%%LR90*%%LS2*%X10000000Y20000000D03*M02*",
    source="window",
  )
  guard! gerber_pads(document) is [pad]
  // The 4-by-3 rectangle is scaled by 2. Its unit-radius hole is removed
  // at x=7 rather than the rectangle center x=8.
  let expected_x = 8.0 + @math.PI / (48.0 - @math.PI)
  assert_true((pad.center.x - expected_x).abs() < 1.0e-12)
  assert_true((pad.center.y - 20.0).abs() < 1.0e-12)
  assert_true((pad.area - (48.0 - @math.PI)).abs() < 1.0e-12)
  assert_false(copper_at(document, { x: 7.0, y: 20.0, }, 0.1))
  assert_true(copper_at(document, { x: 8.1, y: 20.0, }, 0.0))
}

///|
test "invalid standard holes and macro cuts are refused instead of approximated" {
  for
    (definition, commands, reason) in [
      ("%ADD10C,2X0*%", "X0Y0D03*", "圆孔"),
      ("%ADD10R,4X2X2*%", "X0Y0D03*", "圆孔"),
      ("%ADD10O,4X2X2.1*%", "X0Y0D03*", "圆孔"),
      ("%ADD10P,2X4X0X1.5*%", "X0Y0D03*", "圆孔"),
      ("%ADD10C,2X1*%", "X0Y0D02*X1000000D01*", "D01"),
      ("%AMClip*1,1,2,0,0*1,0,1,0.75,0*%%ADD10Clip*%", "X0Y0D03*", "圆孔"),
    ] {
    let result = Ok(
      parse_gerber(
        "%FSLAX46Y46*%%MOMM*%" + definition + "D10*" + commands + "M02*",
        source="bad hole",
      ),
    ) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("bad hole", message))
    assert_true(message.contains(reason))
  }
}

///|
fn macro_flash(definition : String) -> String {
  "%FSLAX46Y46*%%MOMM*%%AMTest*" + definition + "*%%ADD10Test*%D10*X0Y0D03*M02*"
}

///|
test "outline macro computes a non central centroid and accepts concave outlines" {
  let doc = parse_gerber(
    macro_flash("4,1,6,0,0,4,0,4,1,1,1,1,3,0,3,0,0,90"),
    source="L pad",
  )
  guard! gerber_pads(doc) is [pad]
  assert_eq(pad.area, 6.0)
  assert_true((pad.center.x + 1.0).abs() < 1.0e-12)
  assert_true((pad.center.y - 1.5).abs() < 1.0e-12)
  assert_true(copper_at(doc, { x: -0.5, y: 3.0, }, 0.0))
  assert_false(copper_at(doc, { x: -1.5, y: 3.0, }, 0.0))
}

///|
test "thermal, polygon and vector macros use their distinct geometry" {
  let doc = parse_gerber(macro_flash("7,0,0,4,2,1,0"), source="thermal")
  guard! gerber_pads(doc) is [thermal]
  // Independent polar integral over one quadrant, including the axial gaps.
  assert_true((thermal.area - 5.335356442250777).abs() < 1.0e-10)
  assert_true(copper_at(doc, { x: 1.0, y: 1.0, }, 0.0))
  assert_false(copper_at(doc, { x: 0.0, y: 1.5, }, 0.0))
  assert_false(copper_at(doc, { x: 0.6, y: 0.6, }, 0.0))
  let polygon = parse_gerber(macro_flash("5,1,4,0,0,4,45"), source="polygon")
  guard! gerber_pads(polygon) is [square]
  assert_true((square.area - 8.0).abs() < 1.0e-12)
  assert_true(copper_at(polygon, { x: 1.3, y: 1.3, }, 0.0))
  let vector = parse_gerber(macro_flash("20,1,0.5,0,0,2,0,90"), source="vector")
  guard! gerber_pads(vector) is [line]
  assert_eq(line.area, 1.0)
  assert_true((line.center.y - 1.0).abs() < 1.0e-12)
  assert_true(copper_at(vector, { x: 0.0, y: 1.95, }, 0.0))
  assert_false(copper_at(vector, { x: 0.0, y: 2.05, }, 0.0))
}

///|
test "multiple clear circles subtract disjoint area and shift the copper centroid" {
  let doc = parse_gerber(
    macro_flash("21,1,6,4,0,0,0*1,0,1,-1,0*1,0,2,1,0"),
    source="holes",
  )
  guard! gerber_pads(doc) is [pad]
  let area = 24.0 - 1.25 * @math.PI
  assert_true((pad.area - area).abs() < 1.0e-12)
  assert_true((pad.center.x + 0.75 * @math.PI / area).abs() < 1.0e-12)
  assert_false(copper_at(doc, { x: -1.0, y: 0.0, }, 0.0))
  assert_false(copper_at(doc, { x: 1.0, y: 0.0, }, 0.0))
  assert_true(copper_at(doc, { x: 0.0, y: 1.0, }, 0.0))
  for
    (definition, reason) in [
      ("21,1,6,4,0,0,0*1,0,2,0,0*1,0,2,1,0", "相交"),
      ("4,1,4,0,0,2,2,0,2,2,0,0,0,0", "自交"),
    ] {
    let result = Ok(parse_gerber(macro_flash(definition), source="bad macro")) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("bad macro", detail))
    assert_true(detail.contains(reason))
  }
}

///|
test "a layer-clear flash cannot erase copper through its transparent hole" {
  let document = parse_gerber(
    "%FSLAX46Y46*%%MOMM*%%ADD10C,0.25*%%ADD11C,4X1*%" +
    "D10*%TO.P,R1,1*%X0Y0D03*%TO.P,R2,1*%X1500000Y0D03*%TD*%" +
    "%LPC*%%LS2*%D11*X0Y0D03*M02*",
    source="clear ring",
  )
  let hole : Point = { x: 0.0, y: 0.0, }
  let band : Point = { x: 1.5, y: 0.0, }
  assert_true(copper_at(document, hole, 0.1))
  assert_false(copper_at(document, band, 0.1))
  let affected = refs_with_possible_clearance(document)
  assert_false(affected.contains("R1"))
  assert_true(affected.contains("R2"))
}

///|
fn arc_fixture(
  commands : String,
  definition~ : String = "%ADD10C,0.2*%",
) -> String {
  "%FSLAX46Y46*%%MOMM*%" + definition + "D10*" + commands + "M02*"
}

///|
test "circular strokes respect direction, width, endpoints and full turns" {
  let quarter = "X1000000Y0D02*G75*G03*X0Y1000000I-1000000D01*"
  let ccw = parse_gerber(arc_fixture(quarter), source="arc")
  let cw = parse_gerber(
    arc_fixture(quarter.replace(old="G03", new="G02")),
    source="arc",
  )
  let north_east : Point = { x: 0.70710678, y: 0.70710678, }
  let south : Point = { x: 0.0, y: -1.0, }
  assert_true(copper_at(ccw, north_east, 0.0))
  assert_false(copper_at(cw, north_east, 0.0))
  assert_false(copper_at(ccw, south, 0.0))
  assert_true(copper_at(cw, south, 0.0))
  assert_true(copper_at(ccw, { x: 1.0, y: -0.08, }, 0.0))
  assert_false(copper_at(ccw, { x: 1.0, y: -0.15, }, 0.0))
  assert_true(copper_at(ccw, { x: 1.0, y: -0.15, }, 0.06))
  let full = parse_gerber(
    arc_fixture("X1000000Y0D02*G75*G02*I-1000000J0D01*"),
    source="arc",
  )
  assert_true(copper_at(full, south, 0.0))
  assert_false(copper_at(full, { x: 0.0, y: 0.0, }, 0.0))
  let zero = parse_gerber(
    arc_fixture(quarter, definition="%ADD10C,0*%"),
    source="arc",
  )
  assert_false(copper_at(zero, north_east, 0.1))
}

///|
test "radial rounding is conservative for both dark and clear strokes" {
  let arc = "X1000000Y0D02*G75*G03*X0Y1001000I-1000000J0D01*"
  let document = parse_gerber(arc_fixture(arc), source="rounded arc")
  let border : Point = { x: 0.7778, y: 0.7778, }
  let centerline : Point = { x: 0.7072, y: 0.7072, }
  assert_false(copper_at(document, border, 0.0))
  assert_true(copper_at(document, centerline, 0.0))
  guard! document.features[0].kind is Arc(stroke)
  assert_true(stroke.may_cover(border, 0.0))
  assert_false(stroke.may_cover({ x: 0.78, y: 0.78, }, 0.0))
}

///|
test "ambiguous legacy mode and undefined arc geometry report input errors" {
  for
    (command, reason) in [
      ("G03*X0Y1000000I-1000000D01*", "G75"),
      ("G74*G03*X0Y1000000I1000000D01*", "G74"),
      ("G75*G03*X0Y1000000I0J0D01*", "I/J"),
      ("G75*G03*X0Y0I-1000000J0D01*", "终点"),
    ] {
    let result = Ok(
      parse_gerber(arc_fixture("X1000000Y0D02*" + command), source="bad arc"),
    ) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("bad arc", detail))
    assert_true(detail.contains(reason))
  }
}
