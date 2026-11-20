///|
priv struct MacroExpr {
  chars : Array[Char]
  variables : Map[Int32, Double]
  source : String
  mut pos : Int32
}

///|
fn MacroExpr::error(self : MacroExpr, message : String) -> GerberError {
  InvalidGerber(
    self.source,
    "光圈宏表达式：\{message}（\{self.pos + 1}）",
  )
}

///|
fn MacroExpr::peek(self : MacroExpr) -> Char {
  self.chars.get(self.pos).unwrap_or('\u0000')
}

///|
fn MacroExpr::variable(self : MacroExpr) -> Int32 raise GerberError {
  self.pos += 1
  let mut id = 0
  let start = self.pos
  while is_digit(self.peek()) {
    if id > (2147483647 - digit_value(self.peek())) / 10 {
      raise self.error("变量编号过大")
    }
    id = id * 10 + digit_value(self.peek())
    self.pos += 1
  }
  if self.pos == start || id == 0 {
    raise self.error("变量编号必须为正整数")
  }
  id
}

///|
fn MacroExpr::atom(self : MacroExpr, depth : Int32) -> Double raise GerberError {
  let sign = match self.peek() {
    '+' => {
      self.pos += 1
      1.0
    }
    '-' => {
      self.pos += 1
      -1.0
    }
    _ => 1.0
  }
  let value = match self.peek() {
    '$' => self.variables.get(self.variable()).unwrap_or(0.0)
    '(' => {
      if depth >= 32 {
        raise self.error("括号嵌套超过 32 层")
      }
      self.pos += 1
      let value = self.sum(depth + 1)
      if self.peek() != ')' {
        raise self.error("缺少右括号")
      }
      self.pos += 1
      value
    }
    _ => {
      let buffer = StringBuilder()
      while is_digit(self.peek()) || self.peek() == '.' {
        buffer.write_char(self.peek())
        self.pos += 1
      }
      aperture_number(buffer.to_string(), self.source)
    }
  }
  value * sign
}

///|
fn MacroExpr::finite(
  self : MacroExpr,
  value : Double,
) -> Double raise GerberError {
  if value.is_nan() || value.is_inf() {
    raise self.error("数值超出可计算范围")
  }
  value
}

///|
fn MacroExpr::product(
  self : MacroExpr,
  depth : Int32,
) -> Double raise GerberError {
  let mut value = self.atom(depth)
  while self.peek() == 'x' || self.peek() == '/' {
    let op = self.peek()
    self.pos += 1
    let next = self.atom(depth)
    if op == '/' && next == 0.0 {
      raise self.error("除数不能为零")
    }
    value = self.finite(if op == 'x' { value * next } else { value / next })
  }
  value
}

///|
fn MacroExpr::sum(self : MacroExpr, depth : Int32) -> Double raise GerberError {
  let mut value = self.product(depth)
  while self.peek() == '+' || self.peek() == '-' {
    let op = self.peek()
    self.pos += 1
    let next = self.product(depth)
    value = self.finite(if op == '+' { value + next } else { value - next })
  }
  value
}

///|
fn MacroExpr::finish(self : MacroExpr) -> Double raise GerberError {
  let value = self.sum(0)
  if self.pos != self.chars.length() {
    raise self.error("存在多余字符")
  }
  value
}

///|
fn macro_value(
  text : String,
  variables : Map[Int32, Double],
  source : String,
) -> Double raise GerberError {
  let expr : MacroExpr = { chars: to_chars(text), variables, source, pos: 0, }
  expr.finish()
}

///|
fn macro_assign(
  statement : String,
  variables : Map[Int32, Double],
  source : String,
) -> Unit raise GerberError {
  let expr : MacroExpr = {
    chars: to_chars(statement),
    variables,
    source,
    pos: 0,
  }
  let id = expr.variable()
  if expr.peek() != '=' {
    raise expr.error("变量定义缺少等号")
  }
  if variables.contains(id) {
    raise expr.error("不能重新定义变量")
  }
  expr.pos += 1
  variables[id] = expr.finish()
}
