///|
pub(all) suberror InputError {
  InvalidInput(String, String)
}

///|
priv enum CsvState {
  Start
  Bare
  Quoted
  Closed
} derive(Eq)

///|
priv struct CsvRow {
  line : Int32
  fields : Array[String]
}

///|
fn csv_row(
  rows : Array[CsvRow],
  fields : Array[String],
  line : Int32,
  source : String,
) -> Unit raise InputError {
  if fields.length() == 1 && fields[0].trim().is_empty() {
    return
  }
  if rows.length() >= 100_001 {
    raise InvalidInput(source, "最多支持 100000 个器件")
  }
  rows.push({ line, fields, })
}

///|
fn parse_csv(input : String, source : String) -> Array[CsvRow] raise InputError {
  if input.length() > 8_388_608 {
    raise InvalidInput(source, "CSV 超过 8388608 字符单元")
  }
  let rows : Array[CsvRow] = []
  let mut fields : Array[String] = []
  let mut cell = StringBuilder()
  let mut state = Start
  let mut line = 1
  let mut row_line = 1
  let mut after_cr = false
  for index, ch in input.iter2() {
    if index == 0 && ch == '\u{FEFF}' {
      continue
    }
    if after_cr {
      after_cr = false
      if ch == '\n' {
        continue
      }
    }
    match ch {
      '\r' | '\n' => {
        if state == Quoted {
          cell.write_char('\n')
        } else {
          fields.push(cell.to_string())
          csv_row(rows, fields, row_line, source)
          fields = []
          cell = StringBuilder()
          state = Start
          row_line = line + 1
        }
        line += 1
        after_cr = ch == '\r'
      }
      ',' if state != Quoted => {
        fields.push(cell.to_string())
        if fields.length() >= 256 {
          raise InvalidInput(source, "第 \{row_line} 行超过 256 列")
        }
        cell = StringBuilder()
        state = Start
      }
      '"' =>
        match state {
          Start => state = Quoted
          Quoted => state = Closed
          Closed => {
            cell.write_char('"')
            state = Quoted
          }
          Bare =>
            raise InvalidInput(source, "第 \{line} 行的引号位置无效")
        }
      _ => {
        if state == Closed {
          raise InvalidInput(
            source,
            "第 \{line} 行的闭引号后应为逗号或换行",
          )
        }
        cell.write_char(ch)
        if state == Start {
          state = Bare
        }
      }
    }
  }
  if state == Quoted {
    raise InvalidInput(source, "第 \{row_line} 行的引号未闭合")
  }
  fields.push(cell.to_string())
  csv_row(rows, fields, row_line, source)
  rows
}
