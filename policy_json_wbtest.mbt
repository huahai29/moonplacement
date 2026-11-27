///|
test "duplicate configuration paths track decoded names and array indices" {
  let input =
    #|{
    #|  "pad_\u006frigins": [
    #|    {"ref": "R1", "source": "literal }, [ and \"quotes\""},
    #|    {"ref": "J1", "source": "🔎", "\u0073ource": "other"}
    #|  ]
    #|}
  let result = Ok(parse_policy_json(input)) catch { error => Err(error) }
  assert_true(
    result
    is Err(
      InvalidInput(
        "pad_origins[1].source",
        "配置项重复（第 4 行，第 35 列）",
      ),
    ),
  )
  let dotted = Ok(
    parse_policy_json(
      (
        #|{"baseline":{"bad.key":1,"bad.key":2}}
      ),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(dotted is Err(InvalidInput("baseline[\"bad.key\"]", _)))
}

///|
test "policy rejects unknown fields at every configurable object boundary" {
  for
    (input, field) in [
      ("{\"bad\":1}", "bad"),
      ("{\"baseline\":{\"bottom_X\":\"negated\"}}", "baseline.bottom_X"),
      ("{\"delivery\":{\"angle-sing\":1}}", "delivery[\"angle-sing\"]"),
    ] {
    let result = Ok(read_policy(input)) catch { error => Err(error) }
    assert_true(
      result is Err(InvalidInput(path, "未知配置项")) && path == field,
    )
  }
  let imported = Ok(
    matching_policy(placement_import=Some({ "exclude_ref": ["J1"] })),
  ) catch {
    error => Err(error)
  }
  assert_true(imported is Err(InvalidInput("placement_import.exclude_ref", _)))
  let pads = Ok(
    matching_policy(
      pad_origins=Some([
        { "ref": "J1", "mode": "review", "source": "PCB", "dx": 1 },
      ]),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(pads is Err(InvalidInput("pad_origins[0].dx", _)))
}
