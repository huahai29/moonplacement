///|
test "UTF-8 BOM, CRLF, blank line and quoted cells" {
  let text = "\u{FEFF}Ref,Val,Package,PosX,PosY,Rot,Side\r\n\r\n\" r1 \",\"a,\"\"b\"\"\r\nc\",p,1.2,-2,360,Top\r\n"
  let rows = parse_csv(text, "fixture")
  assert_eq(rows.length(), 2)
  assert_eq(rows[1].line, 3)
  assert_eq(rows[1].fields[1], "a,\"b\"\nc")
  let parts = read_placements(text, source="fixture")
  assert_eq(parts.rows["R1"].xy.x, 1.2)
  assert_true(parts.rows["R1"].side is Top)
}

///|
test "JLC columns can be reordered" {
  let parts = read_placements(
    "Rotation,Layer,Designator,Mid Y,Mid X\n-90,Bottom,u3,2,1",
    source="fixture",
  )
  assert_eq(parts.rows["U3"].angle_deg, -90.0)
  assert_eq(parts.rows["U3"].xy.y, 2.0)
  assert_true(parts.rows["U3"].side is Bottom)
}

///|
test "CSV reports physical lines for malformed quotes" {
  let result = Ok(parse_csv("a,b\nx,\"open\nstill open", "delivery")) catch {
    error => Err(error)
  }
  assert_true(
    result is Err(InvalidInput("delivery", "第 2 行的引号未闭合")),
  )
  let result = Ok(parse_csv("a,b\nx,\"closed\"tail", "delivery")) catch {
    error => Err(error)
  }
  assert_true(
    result
    is Err(
      InvalidInput("delivery", "第 2 行的闭引号后应为逗号或换行")
    ),
  )
}

///|
test "ambiguous headers and invalid placement cells are rejected" {
  let header = "Ref,PosX,PosY,Rot,Side\n"
  for
    row in [
      "R1,,2,0,top", "R1,NaN,2,0,top", "R1,1,2,Inf,top", "R1,1,2,0,left", "R1,1,2,0",
      "R1,1,2,0,top,extra", ",1,2,0,top",
    ] {
    let result = Ok(read_placements(header + row, source="baseline")) catch {
      error => Err(error)
    }
    assert_true(result is Err(InvalidInput("baseline 第 2 行", _)), msg=row)
  }
  let result = Ok(
    read_placements(header + "R1,1,2,0,top\nr1,2,1,0,bottom", source="baseline"),
  ) catch {
    error => Err(error)
  }
  assert_true(
    result is Err(InvalidInput("baseline 第 3 行", "位号重复：R1")),
  )
  let result = Ok(
    read_placements(
      "Ref,Designator,PosX,PosY,Rot,Side\nR1,R1,1,2,0,top",
      source="baseline",
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(result is Err(InvalidInput("baseline", _)))
}
