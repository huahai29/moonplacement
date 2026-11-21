///|
extern "js" fn arg_count() -> Int32 = "() => process.argv.length - 2"

///|
extern "js" fn arg(index : Int32) -> String = "(index) => process.argv[index + 2]"

///|
extern "js" fn finish(code : Int32) -> Unit = "(code) => { process.exitCode = code; }"

///|
type FileRead

///|
extern "js" fn read_file(path : String, limit : Int32) -> FileRead =
  #| (path, limit) => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
  #|     try {
  #|       if (!fs.fstatSync(fd).isFile()) return { error: "需要普通文件" };
  #|       const bytes = Buffer.alloc(limit + 1);
  #|       let length = 0;
  #|       while (length < bytes.length) {
  #|         const count = fs.readSync(fd, bytes, length, bytes.length - length, null);
  #|         if (!count) break;
  #|         length += count;
  #|       }
  #|       if (length > limit) return { error: "文件超过 " + limit + " 字节" };
  #|       return { text: new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, length)) };
  #|     } finally {
  #|       fs.closeSync(fd);
  #|     }
  #|   } catch (error) {
  #|     return { error: error.code ?? error.message };
  #|   }
  #| }

///|
extern "js" fn file_error(file : FileRead) -> String = "(file) => file.error ?? ''"

///|
extern "js" fn file_text(file : FileRead) -> String = "(file) => file.text ?? ''"

///|
extern "js" fn write_file(path : String, text : String) -> String =
  #| (path, text) => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     fs.writeFileSync(path, text);
  #|     return '';
  #|   } catch (error) {
  #|     return error.code ?? error.message;
  #|   }
  #| }

///|
fn load_file(
  path : String,
  limit : Int32,
) -> String raise @placement.InputError {
  let file = read_file(path, limit)
  let error = file_error(file)
  if !error.is_empty() {
    raise @placement.InvalidInput(path, error)
  }
  file_text(file)
}

///|
fn load_gerber(
  path : String,
) -> @placement.GerberDocument raise @placement.InputError {
  let text = load_file(path, 8_388_608)
  @placement.parse_gerber(text, source=path) catch {
    @placement.InvalidGerber(field, message) =>
      raise @placement.InvalidInput(field, message)
  }
}

///|
fn usage() -> String {
  "用法：moon run cmd/main --target js -- <基准.csv> <送厂.csv> <配置.json> [顶层.gbr] [底层.gbr] [--panel-cell 行,列] [--html 报告.html]"
}

///|
priv struct CliArgs {
  positional : Array[String]
  html : String?
  cell : (Int32, Int32)?
}

///|
fn cell_index(value : String) -> Int32 raise @placement.InputError {
  let mut n = 0
  if value.is_empty() || value.length() > 5 {
    raise @placement.InvalidInput(
      "panel_cell", "单元格式应为正整数行,列，例如 2,1",
    )
  }
  for _, ch in value.iter2() {
    if ch < '0' || ch > '9' {
      raise @placement.InvalidInput(
        "panel_cell", "单元格式应为正整数行,列，例如 2,1",
      )
    }
    n = n * 10 + ch.to_int() - 48
  }
  if n == 0 {
    raise @placement.InvalidInput("panel_cell", "拼板行列从 1 开始")
  }
  n
}

///|
fn parse_args() -> CliArgs raise @placement.InputError {
  let positional : Array[String] = []
  let mut html : String? = None
  let mut cell = None
  let mut index = 0
  while index < arg_count() {
    let value = arg(index)
    if value == "--html" && index + 1 < arg_count() {
      html = Some(arg(index + 1))
      index += 2
    } else if value == "--panel-cell" {
      if cell is Some(_) || index + 1 >= arg_count() {
        raise @placement.InvalidInput(
          "panel_cell", "--panel-cell 需要且只能提供一次行,列",
        )
      }
      guard arg(index + 1).split(",").map(part => part.to_owned()).collect()
        is [row, column] else {
        raise @placement.InvalidInput(
          "panel_cell", "单元格式应为行,列，例如 2,1",
        )
      }
      cell = Some((cell_index(row), cell_index(column)))
      index += 2
    } else {
      positional.push(value)
      index += 1
    }
  }
  { positional, html, cell, }
}

///|
fn load_layer(
  path : String,
  cell : (Int32, Int32)?,
  reference~ : @placement.GerberDocument? = None,
) -> @placement.GerberDocument raise @placement.InputError {
  let document = load_gerber(path)
  guard cell is Some((row, column)) else { return document }
  @placement.select_panel_cell(document, row~, column~, source=path, reference?) catch {
    @placement.InvalidGerber(field, message) =>
      raise @placement.InvalidInput(field, message)
  }
}

///|
fn run() -> Int32 raise @placement.InputError {
  if arg_count() == 1 && (arg(0) == "--help" || arg(0) == "-h") {
    println(usage())
    return 0
  }
  let args = parse_args()
  let positional = args.positional
  if positional.length() != 3 &&
    positional.length() != 4 &&
    positional.length() != 5 {
    raise @placement.InvalidInput("arguments", usage())
  }
  if args.cell is Some(_) && positional.length() < 4 {
    raise @placement.InvalidInput(
      "panel_cell", "--panel-cell 需要提供 Gerber 铜层",
    )
  }
  let policy = @placement.read_policy(load_file(positional[2], 65_536))
  let baseline = @placement.read_placements(
    load_file(positional[0], 8_388_608),
    source=positional[0],
  )
  let delivery = @placement.read_placements(
    load_file(positional[1], 8_388_608),
    source=positional[1],
  )
  let top = if positional.length() >= 4 {
    Some(load_layer(positional[3], args.cell))
  } else {
    None
  }
  let bottom = if positional.length() >= 5 {
    Some(load_layer(positional[4], args.cell, reference=top))
  } else {
    None
  }
  let result = @placement.audit(
    baseline,
    delivery,
    policy,
    top_gerber=top,
    bottom_gerber=bottom,
  )
  match args.html {
    Some(path) => {
      let html = @placement.render_html(result.report, baseline)
      let error = write_file(path, html)
      if !error.is_empty() {
        raise @placement.InvalidInput(
          path,
          "无法写入 HTML 报告：\{error}",
        )
      }
    }
    None => ()
  }
  println(result.report.stringify(indent=2))
  match result.verdict {
    @placement.Pass => 0
    @placement.Different => 1
    @placement.Indeterminate => 2
  }
}

///|
fn main {
  let code = run() catch {
    @placement.InvalidInput(field, message) => {
      let report : Json = {
        "schema_version": Json(@placement.REPORT_SCHEMA_VERSION),
        "status": Json("input_error"),
        "field": Json(field),
        "message": Json(message),
      }
      println(report.stringify(indent=2))
      64
    }
  }
  finish(code)
}
