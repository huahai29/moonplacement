///|
test "an expected list reports each missing input and records the chosen columns" {
  let policy = matching_policy(
    placement_import=Some({
      "delivery": { "coordinates": "ref", "footprint_prefix": "vendor:" },
      "expected_refs": ["r1", "r2", "r3", "r4", "r5", "r6"],
    }),
  )
  let (baseline, delivery) = read_placement_pair(
    (
      #| Ref,PosX,PosY,Rot,Side,Package
      #| R1,0,0,0,top,0603
      #| R2,10,0,0,top,0603
      #| R3,0,10,0,top,0603
      #| R4,1,1,0,top,0603
      #| X1,2,2,0,top,0603
    ),
    (
      #| Designator,Mid X,Mid Y,Ref X,Ref Y,Rotation,Layer,Footprint
      #| R1,90,90,0,0,0,T,vendor:0603
      #| R2,90,90,10,0,0,T,vendor:0603
      #| R3,90,90,0,10,0,T,vendor:0603
      #| R5,90,90,1,1,0,T,vendor:0603
      #| X2,90,90,2,2,0,T,vendor:0603
    ),
    policy,
    baseline_source="design",
    delivery_source="delivery",
  )
  let result = audit_checked(baseline, delivery, policy)
  assert_true(result.verdict is Different)
  guard! result.report
    is {
      "differences": [
        { "ref": String("R4"), "kind": String("missing"), .. },
        { "ref": String("R5"), "kind": String("missing_baseline"), .. },
        { "ref": String("R6"), "kind": String("missing_both"), .. },
      ],
      "placement_import": {
        "scope": String("expected"),
        "baseline": { "excluded_refs": [String("X1")], .. },
        "delivery": {
          "x_column": String("Ref X"),
          "excluded_refs": [String("X2")],
          ..
        },
        ..
      },
      ..
    }
}

///|
test "the same import settings must be applied before audit" {
  let policy = matching_policy(
    placement_import=Some({ "delivery": { "coordinates": "ref" } }),
  )
  let table = fixture_table("R1,0,0,0,top\nR2,10,0,0,top\nR3,0,10,0,top")
  let result = audit(table, table, policy)
  assert_true(result.verdict is Indeterminate)
  guard! result.report is { "reason": String("invalid_placement_import"), .. }
  let checked = Ok(audit_checked(table, table, policy)) catch {
    error => Err(error)
  }
  guard! checked is Err(InvalidInput("placement_import", _))
}
