///|
/// Transform family estimated by the registration engine.
pub(all) enum TransformModel {
  Rigid
  Similarity
  Affine
}

///|
/// Robust registration result in the source-to-target direction.
///
/// `inlier_mask[i]` is true when correspondence `i` agreed with the consensus
/// set; the residual arrays keep the same length as the anchor list so callers
/// can report per-anchor evidence without recomputing anything.
pub struct Registration {
  model : TransformModel
  transform : Transform2D
  rotation_deg : Double
  scale : Double
  rms_mm : Double
  max_mm : Double
  inlier_mask : Array[Bool]
  residuals_mm : Array[Double]
}

///|
fn centroid(points : Array[Point]) -> Point {
  let mut x = 0.0
  let mut y = 0.0
  for point in points {
    x += point.x
    y += point.y
  }
  let count = points.length().to_double()
  { x: x / count, y: y / count, }
}

///|
/// Closed-form similarity map from `source` to `target`.
///
/// With `allow_scale = false` the uniform scale is pinned to one, which turns
/// the same estimator into a rigid-body fit.
fn fit_similarity(
  source : Array[Point],
  target : Array[Point],
  allow_scale : Bool,
) -> Transform2D? {
  let count = source.length()
  if count < 2 {
    return None
  }
  let source_mean = centroid(source)
  let target_mean = centroid(target)
  let mut dot = 0.0
  let mut cross = 0.0
  let mut norm = 0.0
  for i in 0..<count {
    let px = source[i].x - source_mean.x
    let py = source[i].y - source_mean.y
    let qx = target[i].x - target_mean.x
    let qy = target[i].y - target_mean.y
    dot += px * qx + py * qy
    cross += px * qy - py * qx
    norm += px * px + py * py
  }
  if norm <= 0.0 {
    return None
  }
  let magnitude = @math.hypot(dot, cross)
  if magnitude <= 0.0 {
    return None
  }
  let alpha = if allow_scale { dot / norm } else { dot / magnitude }
  let beta = if allow_scale { cross / norm } else { cross / magnitude }
  Some({
    a: alpha,
    b: -beta,
    c: target_mean.x - (alpha * source_mean.x - beta * source_mean.y),
    d: beta,
    e: alpha,
    f: target_mean.y - (beta * source_mean.x + alpha * source_mean.y),
  })
}

///|
/// Solve a 3x3 system with partial pivoting. `matrix` is row-major with nine
/// entries and `rhs` has three.
///
/// Returns `None` when a pivot collapses below `1e-12`, which is the numerical
/// signature of three nearly collinear anchors.
fn solve3(matrix : Array[Double], rhs : Array[Double]) -> Array[Double]? {
  let a : Array[Double] = [
    matrix[0],
    matrix[1],
    matrix[2],
    rhs[0],
    matrix[3],
    matrix[4],
    matrix[5],
    rhs[1],
    matrix[6],
    matrix[7],
    matrix[8],
    rhs[2],
  ]
  for column in 0..<3 {
    let mut pivot = column
    let mut best = a[column * 4 + column].abs()
    for row in (column + 1)..<3 {
      let candidate = a[row * 4 + column].abs()
      if candidate > best {
        best = candidate
        pivot = row
      }
    }
    if best < 1.0e-12 {
      return None
    }
    if pivot != column {
      for entry in 0..<4 {
        let tmp = a[column * 4 + entry]
        a[column * 4 + entry] = a[pivot * 4 + entry]
        a[pivot * 4 + entry] = tmp
      }
    }
    let diagonal = a[column * 4 + column]
    for row in (column + 1)..<3 {
      let factor = a[row * 4 + column] / diagonal
      for entry in column..<4 {
        a[row * 4 + entry] = a[row * 4 + entry] - factor * a[column * 4 + entry]
      }
    }
  }
  let solution : Array[Double] = [0.0, 0.0, 0.0]
  for step in 0..<3 {
    let row = 2 - step
    let mut sum = a[row * 4 + 3]
    for column in (row + 1)..<3 {
      sum -= a[row * 4 + column] * solution[column]
    }
    solution[row] = sum / a[row * 4 + row]
  }
  Some(solution)
}

///|
/// Least-squares affine map from `source` to `target`, solved through the normal
/// equations of the three-parameter rows `[x, y, 1]`.
fn fit_affine(source : Array[Point], target : Array[Point]) -> Transform2D? {
  let count = source.length()
  if count < 3 {
    return None
  }
  let mut sxx = 0.0
  let mut sxy = 0.0
  let mut syy = 0.0
  let mut sx = 0.0
  let mut sy = 0.0
  let mut qxx = 0.0
  let mut qxy = 0.0
  let mut qx = 0.0
  let mut qyx = 0.0
  let mut qyy = 0.0
  let mut qy = 0.0
  for i in 0..<count {
    let px = source[i].x
    let py = source[i].y
    let tx = target[i].x
    let ty = target[i].y
    sxx += px * px
    sxy += px * py
    syy += py * py
    sx += px
    sy += py
    qxx += tx * px
    qxy += tx * py
    qx += tx
    qyx += ty * px
    qyy += ty * py
    qy += ty
  }
  let matrix : Array[Double] = [
    sxx,
    sxy,
    sx,
    sxy,
    syy,
    sy,
    sx,
    sy,
    count.to_double(),
  ]
  let rows_x = match solve3(matrix, [qxx, qxy, qx]) {
    Some(value) => value
    None => return None
  }
  let rows_y = match solve3(matrix, [qyx, qyy, qy]) {
    Some(value) => value
    None => return None
  }
  Some({
    a: rows_x[0],
    b: rows_x[1],
    c: rows_x[2],
    d: rows_y[0],
    e: rows_y[1],
    f: rows_y[2],
  })
}

///|
fn fit_model(
  source : Array[Point],
  target : Array[Point],
  model : TransformModel,
) -> Transform2D? {
  match model {
    Affine => fit_affine(source, target)
    Rigid => fit_similarity(source, target, false)
    Similarity => fit_similarity(source, target, true)
  }
}

///|
fn residual_distances(
  transform : Transform2D,
  source : Array[Point],
  target : Array[Point],
) -> Array[Double] {
  let distances : Array[Double] = []
  for i in 0..<source.length() {
    distances.push(magnitude(difference(transform.apply(source[i]), target[i])))
  }
  distances
}

///|
/// Deterministic minimal samples. The anchor list is capped at 64 entries, so
/// the full enumeration stays small and keeps repeated runs reproducible.
fn sample_combinations(count : Int32, size : Int32) -> Array[Array[Int32]] {
  let samples : Array[Array[Int32]] = []
  if size == 2 {
    for i in 0..<count {
      for j in (i + 1)..<count {
        samples.push([i, j])
      }
    }
  } else if size == 3 {
    for i in 0..<count {
      for j in (i + 1)..<count {
        for k in (j + 1)..<count {
          samples.push([i, j, k])
        }
      }
    }
  }
  samples
}

///|
/// Robustly estimate a `source -> target` transform for `model`.
///
/// Every minimal sample is tried, then the best consensus set is refit twice.
/// Enumerating instead of drawing random samples keeps the report deterministic
/// for a fixed input, which the CI and the tolerance regression rely on.
pub fn register(
  source : Array[Point],
  target : Array[Point],
  model : TransformModel,
  threshold_mm : Double,
) -> Registration? {
  let count = source.length()
  if count != target.length() || count < 2 {
    return None
  }
  let sample_size : Int32 = match model {
    Affine => 3
    _ => 2
  }
  if count < sample_size {
    return None
  }
  let samples = sample_combinations(count, sample_size)
  let mut best_mask : Array[Bool] = []
  let mut best_transform : Transform2D? = None
  let mut best_count = -1
  let mut best_error = 0.0
  for sample in samples {
    let sample_source : Array[Point] = []
    let sample_target : Array[Point] = []
    for index in sample {
      sample_source.push(source[index])
      sample_target.push(target[index])
    }
    match fit_model(sample_source, sample_target, model) {
      None => ()
      Some(transform) => {
        let distances = residual_distances(transform, source, target)
        let mask : Array[Bool] = []
        let mut inliers = 0
        let mut error = 0.0
        for distance in distances {
          if distance <= threshold_mm {
            mask.push(true)
            inliers += 1
            error += distance * distance
          } else {
            mask.push(false)
          }
        }
        if inliers > best_count || (inliers == best_count && error < best_error) {
          best_count = inliers
          best_error = error
          best_mask = mask
          best_transform = Some(transform)
        }
      }
    }
  }
  let mut current = match best_transform {
    Some(transform) => transform
    None => return None
  }
  let mut mask = best_mask
  for _ in 0..<2 {
    let inlier_source : Array[Point] = []
    let inlier_target : Array[Point] = []
    for i in 0..<count {
      if mask[i] {
        inlier_source.push(source[i])
        inlier_target.push(target[i])
      }
    }
    let refit = match fit_model(inlier_source, inlier_target, model) {
      Some(transform) => transform
      None => break
    }
    current = refit
    let distances = residual_distances(current, source, target)
    let next : Array[Bool] = []
    for distance in distances {
      next.push(distance <= threshold_mm)
    }
    mask = next
  }
  let distances = residual_distances(current, source, target)
  let final_mask : Array[Bool] = []
  let mut inliers = 0
  let mut sum_squares = 0.0
  let mut worst_inlier = 0.0
  for i in 0..<count {
    let inside = distances[i] <= threshold_mm && mask[i]
    final_mask.push(inside)
    if inside {
      inliers += 1
      sum_squares += distances[i] * distances[i]
      worst_inlier = worst_inlier.max(distances[i])
    }
  }
  if inliers == 0 {
    return None
  }
  Some({
    model,
    transform: current,
    rotation_deg: current.rotation_deg(),
    scale: current.scale(),
    rms_mm: (sum_squares / inliers.to_double()).sqrt(),
    max_mm: worst_inlier,
    inlier_mask: final_mask,
    residuals_mm: distances,
  })
}

///|
/// Number of correspondences that agreed with the robust consensus.
pub fn Registration::inlier_count(self : Registration) -> Int32 {
  let mut total = 0
  for value in self.inlier_mask {
    if value {
      total += 1
    }
  }
  total
}
