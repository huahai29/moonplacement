///|
extern "js" fn read_cases() -> String = "() => process.getBuiltinModule('node:fs').readFileSync(0, 'utf8')"

///|
fn points(rows : Array[Json]) -> Array[@mp.Point] {
  rows.map(row => {
    guard row is [Number(x, ..), Number(y, ..)] else {
      abort("expected a two-dimensional point")
    }
    @mp.Point::new(x, y)
  })
}

///|
fn evaluate(request : Json) -> Json {
  guard request
    is {
      "model": String(model),
      "source": Array(source),
      "target": Array(target),
      "threshold": Number(threshold, ..),
      ..
    } else {
    abort("invalid registration case")
  }
  let model : @mp.TransformModel = match model {
    "rigid" => Rigid
    "similarity" => Similarity
    "affine" => Affine
    _ => abort("unknown registration model")
  }
  guard @mp.register(points(source), points(target), model, threshold)
    is Some(result) else {
    return Json(null)
  }
  let t = result.transform
  {
    "matrix": Json([[t.a, t.d], [t.b, t.e]]),
    "translation": Json([t.c, t.f]),
    "rotation_deg": Json(result.rotation_deg),
    "scale": Json(result.scale),
    "mask": Json(result.inlier_mask),
    "residuals_mm": Json(result.residuals_mm),
    "rms_mm": Json(result.rms_mm),
    "max_mm": Json(result.max_mm),
  }
}

///|
fn main {
  let cases = @json.parse(read_cases()) catch {
    _ => abort("expected JSON registration cases")
  }
  guard cases is Array(requests) else {
    abort("expected an array of registration cases")
  }
  println(Json(requests.map(evaluate)).stringify())
}
