///|
fn squared_length(point : Point) -> Double {
  point.x * point.x + point.y * point.y
}

///|
fn max_squared_distance(
  points : Array[Point],
  center : Point,
  cutoff : Double,
) -> Double {
  let mut worst = 0.0
  for point in points {
    worst = worst.max(squared_length(difference(point, center)))
    if worst >= cutoff {
      break
    }
  }
  worst
}

///|
fn circumcenter(a : Point, b : Point, c : Point) -> Point? {
  let ab = difference(b, a)
  let ac = difference(c, a)
  let determinant = 2.0 * (ab.x * ac.y - ab.y * ac.x)
  if determinant == 0.0 {
    return None
  }
  let ab_squared = squared_length(ab)
  let ac_squared = squared_length(ac)
  let x = (ac.y * ab_squared - ab.y * ac_squared) / determinant
  let y = (ab.x * ac_squared - ac.x * ab_squared) / determinant
  // The enclosing circle's center is inside the offsets' bounding box.
  // Normalization places every offset in [-1, 1] on each axis.
  if !(x.abs() <= 2.0 && y.abs() <= 2.0) {
    return None
  }
  Some({ x: a.x + x, y: a.y + y, })
}

///|
// A smallest enclosing circle is supported by a point, a diameter pair, or
// three boundary points. Enumerate these centers for the bounded anchor set.
fn minimax_translation(offsets : Array[Point]) -> Point {
  let origin = offsets[0]
  let relative = offsets.map(point => difference(point, origin))
  let mut scale = 0.0
  for point in relative {
    scale = scale.max(point.x.abs()).max(point.y.abs())
  }
  if scale == 0.0 {
    return origin
  }
  let normalized = relative.map(point => {
    x: point.x / scale,
    y: point.y / scale,
  })
  let mut center = normalized[0]
  // The initial center is at the origin, so squared distances are at most 2.
  let mut radius_squared = max_squared_distance(normalized, center, 2.0)
  for i, a in normalized {
    for j in (i + 1)..<normalized.length() {
      let b = normalized[j]
      let midpoint = { x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5, }
      let required = max_squared_distance(normalized, midpoint, radius_squared)
      if required < radius_squared {
        center = midpoint
        radius_squared = required
      }
    }
  }
  for i, a in normalized {
    for j in (i + 1)..<normalized.length() {
      for k in (j + 1)..<normalized.length() {
        if circumcenter(a, normalized[j], normalized[k]) is Some(candidate) {
          let required = max_squared_distance(
            normalized, candidate, radius_squared,
          )
          if required < radius_squared {
            center = candidate
            radius_squared = required
          }
        }
      }
    }
  }
  { x: origin.x + center.x * scale, y: origin.y + center.y * scale, }
}
