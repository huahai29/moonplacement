///|
test "X2 updates and deletes dictionary entries without rewriting past objects" {
  let text =
    #|%FSLAX46Y46*%%MOMM*%
    #|%TF.ProjectId,Board Name,123,rev*%
    #|%TA.AperFunction,ComponentPad*%%ADD10C,0.5*%
    #|%TA.AperFunction,ViaPad*%%ADD11C,0.5*%
    #|%TD.AperFunction*%%ADD12C,0.5*%
    #|%TO.C,U3*%%TO.P,U3,1,Signal Name*%%TO.N,Net A*%
    #|D10*X1000000Y0D03*
    #|%TD.P*%D11*X2000000Y0D03*
    #|G04 #@! TO.P,C7,2,Another Pin*
    #|D12*X3000000Y0D03*
    #|%TD*%D10*X4000000Y0D03*M02*
  let doc = parse_gerber(text, source="X2 dictionaries")
  assert_eq(
    doc.file_attributes.get(".ProjectId"),
    Some(["Board Name", "123", "rev"]),
  )
  guard! doc.features is [one, two, three, four]
  assert_eq((one.refdes, one.pin), (Some("U3"), Some("1")))
  assert_eq(one.object_attributes.get(".P"), Some(["U3", "1", "Signal Name"]))
  assert_eq(
    one.aperture_attributes.get(".AperFunction"),
    Some(["ComponentPad"]),
  )
  assert_eq((two.refdes, two.pin), (Some("U3"), None))
  assert_eq(two.object_attributes.get(".N"), Some(["Net A"]))
  assert_eq(two.aperture_attributes.get(".AperFunction"), Some(["ViaPad"]))
  assert_eq((three.refdes, three.pin), (Some("C7"), Some("2")))
  assert_true(three.aperture_attributes.is_empty())
  assert_true(four.object_attributes.is_empty())
  assert_eq(four.aperture_attributes, one.aperture_attributes)
}

///|
test "AB pin ownership and X2 snapshots survive either SR selection path" {
  let text =
    #|%FSLAX46Y46*%%MOMM*%
    #|%TA.AperFunction,ComponentPad*%%ADD10C,0.5*%%TD*%
    #|%ABD21*%%TO.P,D1,1,A*%D10*X0Y0D03*%TD.P*%%AB*%
    #|%TA.BlockLabel,Pair*%%ABD20*%%TD.BlockLabel*%
    #|D21*X1000000Y1000000D03*
    #|%TO.P,C7,2,B*%D10*X3000000Y1000000D03*%TD*%%AB*%
    #|%ABD22*%D10*X0Y0D03*%AB*%
    #|%SRX2Y1I20J0*%
    #|%TO.P,WRONG,99*%D20*X10000000Y10000000D03*%TD.P*%
    #|%TO.P,R2,7*%D22*X16000000Y11000000D03*%TD*%%SR*%M02*
  let whole = parse_gerber(text, source="expanded X2")
  assert_true(whole.repeated_refs.contains("D1"))
  for column in 1..<=2 {
    let direct = parse_gerber_cell(text, source="direct X2", row=1, column~)
    let selected = select_panel_cell(
      whole,
      source="selected X2",
      row=1,
      column~,
    )
    guard! direct.features is [d1, c7, r2]
    assert_eq(
      direct.features.map(f => (f.refdes, f.pin)),
      selected.features.map(f => (f.refdes, f.pin)),
    )
    assert_eq(
      direct.features.map(f => f.object_attributes),
      selected.features.map(f => f.object_attributes),
    )
    assert_eq((d1.refdes, d1.pin), (Some("D1"), Some("1")))
    assert_eq((c7.refdes, c7.pin), (Some("C7"), Some("2")))
    assert_eq((r2.refdes, r2.pin), (Some("R2"), Some("7")))
    assert_eq(c7.object_attributes.get(".P"), Some(["C7", "2", "B"]))
    assert_eq(c7.block_attributes[0].object.get(".P"), Some(["WRONG", "99"]))
    assert_eq(
      c7.block_attributes[0].aperture.get(".BlockLabel"),
      Some(["Pair"]),
    )
    assert_eq(r2.block_attributes[0].object.get(".P"), Some(["R2", "7"]))
  }
}
