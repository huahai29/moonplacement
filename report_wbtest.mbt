///|
test "offline report renders an offset and escapes the designator" {
  let baseline = fixture_table(
    "R1,1,1,0,top\nR2,4,1,0,top\nR3,1,4,0,top\nD<&>,4,4,0,top",
  )
  let delivery = fixture_table(
    "R1,1,1,0,top\nR2,4,1,0,top\nR3,1,4,0,top\nD<&>,4.3,4,0,top",
  )
  let result = audit(baseline, delivery, matching_policy())
  assert_true(result.verdict is Different)
  let html = render_html(result.report, baseline)
  assert_true(html.contains("D&lt;&amp;&gt;"))
  assert_false(html.contains("D<&>"))
  assert_true(html.contains("marker-end=\"url(#arrow)\""))
}
