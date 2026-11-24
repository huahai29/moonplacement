///|
test "layer declarations survive panel selection and identify wrong audit slots" {
  let declarations = "%TF.FileFunction,Copper,L2,Bot,Signal*%"
  let body = "%FSLAX46Y46*%%MOMM*%%ADD10C,0.5*%D10*" +
    "%SRX2Y2I20J20*%X1000000Y1000000D03*%TD*%%SR*%M02*"
  let document = parse_gerber_cell(
    declarations + body,
    row=2,
    column=2,
    source="declared-bottom.gbr",
  )
  assert_eq(
    document.file_function,
    Some("TF.FileFunction,Copper,L2,Bot,Signal"),
  )
  let tables = fixture_table(
    "R1,1,1,0,top\nR2,7,1,0,top\nR3,1,7,0,top\nD1,4,4,0,top",
  )
  let policy = matching_policy()
  let checked = Ok(
    audit_checked(tables, tables, policy, top_gerber=Some(document)),
  ) catch {
    error => Err(error)
  }
  guard! checked is Err(InvalidInput("declared-bottom.gbr", message))
  assert_true(message.contains("顶层铜"))
  let compatible = audit(tables, tables, policy, top_gerber=Some(document))
  assert_true(compatible.verdict is Indeterminate)
  guard! compatible.report
    is {
      "status": String("indeterminate"),
      "reason": String("invalid_gerber_layer"),
      "pad_status": String("skipped"),
      "pad_evidence": [],
      "pad_warnings": [{ "side": String("top"), "message": String(_), .. }],
      ..
    }
  assert_true(
    render_html(compatible.report, tables).contains(
      "Gerber 板面或用途不符，未核验",
    ),
  )
  let bottom = audit_checked(
    tables,
    tables,
    policy,
    bottom_gerber=Some(document),
  )
  assert_true(bottom.verdict is Pass)
}

///|
test "legacy FileFunction comments are read and conflicting declarations are rejected" {
  let body = "%FSLAX46Y46*%%MOMM*%%ADD10C,0.5*%D10*X0Y0D03*M02*"
  let comment = "G04 #@! TF.FileFunction,Copper,L1,Top,Hatched*"
  let same = "%TF.FileFunction,Copper,L1,Top,Hatched*%"
  let document = parse_gerber(comment + same + body, source="legacy.gbr")
  assert_eq(
    document.file_function,
    Some("TF.FileFunction,Copper,L1,Top,Hatched"),
  )
  for
    invalid in [
      "%TF.FileFunction*%",
      "%TF.FileFunction,Copper,L1*%",
      "%TF.FileFunction,Copper,L3,Top*%",
      "%TF.FileFunction,Copper,L0,Bot*%",
      "%TF.FileFunction,Copper,Missing,Top*%",
      "%TF.FileFunction,Copper,L1,Top,Unknown*%",
      comment + "%TF.FileFunction,Copper,L2,Bot*%",
    ] {
    let parsed = Ok(parse_gerber(invalid + body, source="invalid.gbr")) catch {
      error => Err(error)
    }
    guard! parsed is Err(InvalidGerber("invalid.gbr", message))
    assert_true(message.contains(".FileFunction"))
  }
}
