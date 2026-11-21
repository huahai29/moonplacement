///|
test "selecting a panel cell retains later local clear operations and normalizes offsets" {
  let doc = parse_gerber(
    "%FSLAX46Y46*%%MOMM*%%ADD10C,1*%D10*%SRX2Y1I10J0*%" +
    "%TO.P,R1,1*%X1000000Y2000000D03*%TD*%%SR*%" +
    "%LPC*%X11000000Y2000000D03*M02*",
    source="panel",
  )
  let first = select_panel_cell(doc, row=1, column=1, source="panel")
  let second = select_panel_cell(doc, row=1, column=2, source="panel")
  let p : Point = { x: 1.0, y: 2.0, }
  assert_true(copper_at(first, p, 0.0))
  assert_false(copper_at(second, p, 0.0))
  assert_false(first.repeated_refs.contains("R1"))
  guard! pad_evidence(second, ["R1"], [p], 0.1) is [PossibleClearance(witness)]
  assert_eq(witness.pin, Some("1"))
  assert_eq(witness.pad_center.x, 1.0)
  assert_eq(witness.clear_bounds.upper.x, 1.5)
}

///|
test "panel cell selection keeps duplicate instances inside a single cell ambiguous" {
  let doc = parse_gerber(
    "%FSLAX46Y46*%%MOMM*%%ADD10C,0.5*%%ABD20*%D10*%TO.P,D1,1*%" +
    "X0Y0D03*%TD*%%AB*%D20*%SRX2Y1I10J0*%X1000000Y2000000D03*" +
    "X2000000Y2000000D03*%SR*%M02*",
    source="blocks within each cell",
  )
  let cell = select_panel_cell(doc, row=1, column=2, source="panel")
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
}
