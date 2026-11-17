///|
/// A 2D affine map `p' = M * p + t` with `M = [[a, b], [d, e]]`.
///
/// The same struct carries rigid, similarity and affine fits, so the audit
/// report can describe every accepted alignment with one type.
pub struct Transform2D {
  a : Double
  b : Double
  c : Double
  d : Double
  e : Double
  f : Double
}

///|
pub fn Transform2D::identity() -> Transform2D {
  { a: 1.0, b: 0.0, c: 0.0, d: 0.0, e: 1.0, f: 0.0, }
}

///|
pub fn Transform2D::apply(self : Transform2D, p : Point) -> Point {
  {
    x: self.a * p.x + self.b * p.y + self.c,
    y: self.d * p.x + self.e * p.y + self.f,
  }
}

///|
pub fn Transform2D::translation(self : Transform2D) -> Point {
  { x: self.c, y: self.f, }
}

///|
pub fn Transform2D::determinant(self : Transform2D) -> Double {
  self.a * self.e - self.b * self.d
}

///|
/// Uniform scale of the linear part. For a rigid or similarity map this is the
/// exact scale factor; for a general affine map it is the geometric mean of the
/// two singular values.
pub fn Transform2D::scale(self : Transform2D) -> Double {
  self.determinant().abs().sqrt()
}

///|
/// Counter-clockwise rotation of the image of the X axis, in degrees.
pub fn Transform2D::rotation_deg(self : Transform2D) -> Double {
  @math.atan2(self.d, self.a) * 180.0 / @math.PI
}

///|
pub fn Transform2D::with_translation(
  self : Transform2D,
  t : Point,
) -> Transform2D {
  { a: self.a, b: self.b, c: t.x, d: self.d, e: self.e, f: t.y, }
}

///|
/// Exact quarter-turn rotation followed by a translation. The coefficients are
/// integers so that existing quarter-turn reports stay bit-for-bit stable.
pub fn Transform2D::quarter_turns(turns : Int32, t : Point) -> Transform2D {
  match turns {
    1 => { a: 0.0, b: -1.0, c: t.x, d: 1.0, e: 0.0, f: t.y, }
    2 => { a: -1.0, b: 0.0, c: t.x, d: 0.0, e: -1.0, f: t.y, }
    3 => { a: 0.0, b: 1.0, c: t.x, d: -1.0, e: 0.0, f: t.y, }
    _ => { a: 1.0, b: 0.0, c: t.x, d: 0.0, e: 1.0, f: t.y, }
  }
}

///|
/// Counter-clockwise rotation by `degrees` with a uniform scale, followed by a
/// translation.
pub fn Transform2D::rotation(
  degrees : Double,
  t : Point,
  scale~ : Double = 1.0,
) -> Transform2D {
  let radians = degrees * @math.PI / 180.0
  let cos = @math.cos(radians)
  let sin = @math.sin(radians)
  {
    a: scale * cos,
    b: -scale * sin,
    c: t.x,
    d: scale * sin,
    e: scale * cos,
    f: t.y,
  }
}
