///|
test "selecting a panel cell retains later local clear operations and normalizes offsets" {
  let text = "%FSLAX46Y46*%%MOMM*%%ADD10C,1*%D10*X12000000Y2000000D03*%SRX2Y1I10J0*%" +
    "%TO.P,R1,1*%X1000000Y2000000D03*%TD*%%SR*%" +
    "%LPC*%X11000000Y2000000D03*M02*"
  let doc = parse_gerber(text, source="panel")
  let first = select_panel_cell(doc, row=1, column=1, source="panel")
  let second = select_panel_cell(doc, row=1, column=2, source="panel")
  let direct = parse_gerber_cell(text, row=1, column=2, source="panel")
  let p : Point = { x: 1.0, y: 2.0, }
  assert_true(copper_at(first, p, 0.0))
  assert_false(copper_at(second, p, 0.0))
  assert_false(first.repeated_refs.contains("R1"))
  guard! pad_evidence(second, ["R1"], [p], 0.1) is [PossibleClearance(witness)]
  assert_eq(witness.pin, Some("1"))
  assert_eq(witness.pad_center.x, 1.0)
  assert_eq(witness.clear_bounds.upper.x, 1.5)
  assert_eq(direct.features.length(), 3)
  guard! pad_evidence(direct, ["R1"], [p], 0.1) is [PossibleClearance(copy)]
  assert_eq(direct.warnings, second.warnings)
  assert_eq(copy.pin, witness.pin)
  assert_eq(copy.pad_index, witness.pad_index)
  assert_eq(copy.clear_index, witness.clear_index)
  assert_eq(copy.clear_statement, witness.clear_statement)
  assert_eq(copy.clear_bounds.upper.x, witness.clear_bounds.upper.x)
}

///|
test "direct and expanded SR selection yield the same audit across rows and columns" {
  let table = fixture_table(
    "R1,1,1,0,top\nR2,4,1,0,top\nR3,1,4,0,top\nD1,4,4,0,top",
  )
  let policy = matching_policy()
  for (rows, columns) in [(1, 4), (3, 1), (3, 4)] {
    let text = "%FSLAX46Y46*%%MOMM*%%ADD10C,0.5*%D10*" +
      "%SRX\{columns}Y\{rows}I12.5J15.25*%" +
      "%TO.P,R1,1*%X1000000Y1000000D03*%TO.P,R2,1*%X4000000Y1000000D03*" +
      "%TO.P,R3,1*%X1000000Y4000000D03*%TO.P,D1,1*%X4000000Y4000000D03*%TD*%" +
      "%LPC*%X4000000Y4000000D03*%SR*%" +
      "%LPD*%X10000000Y1000000D03*M02*"
    let full = parse_gerber(text, source="panel")
    for row in 1..<=rows {
      for column in 1..<=columns {
        let direct = parse_gerber_cell(text, row~, column~, source="panel")
        let eager = select_panel_cell(full, row~, column~, source="panel")
        let actual = audit(table, table, policy, top_gerber=Some(direct))
        let expected = audit(table, table, policy, top_gerber=Some(eager))
        assert_true(actual.verdict is Indeterminate)
        assert_eq(actual.report.stringify(), expected.report.stringify())
      }
    }
  }
}

///|
test "panel cell selection keeps duplicate instances inside a single cell ambiguous" {
  let text = "%FSLAX46Y46*%%MOMM*%%ADD10C,0.5*%%ABD20*%D10*%TO.P,D1,1*%" +
    "X0Y0D03*%TD*%%AB*%D20*%SRX2Y1I10J0*%X1000000Y2000000D03*" +
    "X2000000Y2000000D03*%SR*%M02*"
  let cell = parse_gerber_cell(text, row=1, column=2, source="panel")
  assert_true(cell.repeated_refs.contains("D1"))
  guard! pad_evidence(cell, ["D1"], [{ x: 1.0, y: 2.0, }], 0.1)
    is [RepeatedReference]
}

///|
test "bottom layer reuses a common cell boundary rather than deriving its own grid origin" {
  let head = "%FSLAX46Y46*%%MOMM*%%ADD10C,0.5*%D10*%SRX2Y1I10J0*%"
  let tail = "%SR*%M02*"
  let top = parse_gerber(
    head + "X1000000Y0D03*X5000000D03*" + tail,
    source="top",
  )
  let selected = select_panel_cell(top, row=1, column=2, source="top")
  let bottom = parse_gerber(head + "X3000000Y0D03*" + tail, source="bottom")
  let cell = select_panel_cell(
    bottom,
    row=1,
    column=2,
    source="bottom",
    reference=selected,
  )
  assert_true(copper_at(cell, { x: 3.0, y: 0.0, }, 0.0))
  let shifted = parse_gerber(head + "X13000000Y0D03*" + tail, source="bottom")
  let result = Ok(
    select_panel_cell(
      shifted,
      row=1,
      column=2,
      source="bottom",
      reference=selected,
    ),
  ) catch {
    error => Err(error)
  }
  guard! result is Err(InvalidGerber("bottom", detail))
  assert_true(detail.contains("网格原点或范围不一致"))
  let direct = parse_gerber_cell(
    head + "X3000000Y0D03*" + tail,
    row=1,
    column=2,
    source="bottom",
    reference=selected,
  )
  assert_true(copper_at(direct, { x: 3.0, y: 0.0, }, 0.0))
}

///|
test "direct SR selection checks boundaries and rejects more than one real grid" {
  let head = "%FSLAX46Y46*%%MOMM*%%ADD10C,1*%D10*"
  let grid = "%SRX2Y1I10J0*%X0Y0D03*%SR*%"
  for
    (body, reason) in [
      (grid + "X5000000Y0D03*", "跨越拼板单元边界"),
      ("%SRX2Y1I1J0*%X0Y0D03*%SR*%", "重叠、相切"),
      (grid + grid, "恰好有一组"),
    ] {
    let result = Ok(
      parse_gerber_cell(head + body + "M02*", row=1, column=2, source="panel"),
    ) catch {
      error => Err(error)
    }
    guard! result is Err(InvalidGerber("panel", detail))
    assert_true(detail.contains(reason))
  }
}

///|
test "direct SR selection retains a single base above the whole-panel budget" {
  let content = StringBuilder()
  content.write_string(
    "%FSLAX46Y46*%%MOMM*%%ADD10C,0.4*%D10*%SRX100Y100I10J10*%",
  )
  for _ in 0..<21 {
    content.write_string("X1250000Y750000D03*")
  }
  content.write_string("%SR*%M02*")
  let text = content.to_string()
  let cell = parse_gerber_cell(text, row=100, column=100, source="panel")
  assert_eq(cell.features.length(), 21)
  assert_true(copper_at(cell, { x: 1.25, y: 0.75, }, 0.0))
  let whole = Ok(parse_gerber(text, source="panel")) catch {
    error => Err(error)
  }
  guard! whole is Err(InvalidGerber("panel", detail))
  assert_true(detail.contains("累计上限"))
}
