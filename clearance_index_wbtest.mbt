///|
test "indexed clearance matches reverse drawing order across branches" {
  let items : Array[ClearObject] = []
  let shape = Circle(0.3)
  for i in 0..<256 {
    let center : Point = {
      x: (i * 31 % 41).to_double() * 0.2,
      y: (i * 17 % 23).to_double() * 0.2,
    }
    let kind = if i % 7 == 0 {
      Flash(
        RoundHole(shape, { x: 0.0, y: 0.0, }, { x: 0.0, y: 0.0, }, 0.2),
        center,
      )
    } else {
      Flash(shape, center)
    }
    items.push({
      index: i,
      feature: {
        kind,
        dark: false,
        refdes: None,
        pin: None,
        statement_number: i + 1,
        block_instance: None,
      },
      bounds: bounds_at(center, 0.3),
    })
  }
  // The linear oracle considers objects from latest to earliest.
  let original = items[:].to_owned()
  let tree = clearance_index(items)
  for x in 0..<45 {
    for y in 0..<25 {
      let center : Point = { x: x.to_double() * 0.2, y: y.to_double() * 0.2, }
      let radius = 0.05
      let pad = bounds_at(center, radius)
      let after = (x * 13 + y * 7) % 256
      let mut expected = None
      for n in 0..<original.length() {
        let item = original[original.length() - n - 1]
        if item.index <= after {
          break
        }
        if item.bounds.overlaps(pad) &&
          clear_may_cover(item.feature.kind, center, radius) {
          expected = Some(item.index)
          break
        }
      }
      let got = find_clearance(tree, pad, center, radius, after, None)
      assert_eq(got.map(item => item.index), expected)
    }
  }
}
