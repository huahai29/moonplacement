///|
priv struct ClearObject {
  index : Int32
  feature : GerberFeature
  bounds : GerberBounds
}

///|
priv struct ClearanceBranch {
  bounds : GerberBounds
  latest : Int32
  contents : ClearanceTree
}

///|
priv enum ClearanceTree {
  Leaf(Array[ClearObject])
  Children(ClearanceBranch, ClearanceBranch)
}

///|
fn center_axis(bounds : GerberBounds, by_x : Bool) -> Double {
  if by_x {
    bounds.lower.x * 0.5 + bounds.upper.x * 0.5
  } else {
    bounds.lower.y * 0.5 + bounds.upper.y * 0.5
  }
}

///|
fn clearance_index(items : Array[ClearObject]) -> ClearanceBranch {
  let mut bounds = items[0].bounds
  let mut latest = 0
  for item in items {
    bounds = bounds.union(item.bounds)
    latest = latest.max(item.index)
  }
  if items.length() <= 16 {
    return { bounds, latest, contents: Leaf(items), }
  }
  let by_x = bounds.upper.x - bounds.lower.x >= bounds.upper.y - bounds.lower.y
  items.sort_by((a, b) => {
    let x = center_axis(a.bounds, by_x)
    let y = center_axis(b.bounds, by_x)
    if x < y {
      -1
    } else if x > y {
      1
    } else {
      a.index.compare(b.index)
    }
  })
  let mid = items.length() / 2
  let left = clearance_index(items[:mid].to_owned())
  let right = clearance_index(items[mid:].to_owned())
  let contents = if left.latest >= right.latest {
    Children(left, right)
  } else {
    Children(right, left)
  }
  { bounds, latest, contents, }
}

///|
fn find_clearance(
  branch : ClearanceBranch,
  pad : GerberBounds,
  center : Point,
  radius : Double,
  after : Int32,
  best : ClearObject?,
) -> ClearObject? {
  let minimum = match best {
    Some(item) => item.index
    None => after
  }
  if branch.latest <= minimum || !branch.bounds.overlaps(pad) {
    return best
  }
  match branch.contents {
    Leaf(items) => {
      let mut found = best
      let mut index = minimum
      for item in items {
        if item.index > index &&
          item.bounds.overlaps(pad) &&
          clear_may_cover(item.feature.kind, center, radius) {
          index = item.index
          found = Some(item)
        }
      }
      found
    }
    Children(left, right) => {
      let found = find_clearance(left, pad, center, radius, after, best)
      find_clearance(right, pad, center, radius, after, found)
    }
  }
}
