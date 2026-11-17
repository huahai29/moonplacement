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
  "用法：moon run cmd/main --target js -- <基准.csv> <送厂.csv> <配置.json> [顶层.gbr] [底层.gbr] [--html 报告.html]"
}

///|
priv struct CliArgs {
  positional : Array[String]
  html : String?
}

///|
fn parse_args() -> CliArgs {
  let positional : Array[String] = []
  let mut html : String? = None
  let mut index = 0
  while index < arg_count() {
    let value = arg(index)
    if value == "--html" && index + 1 < arg_count() {
      html = Some(arg(index + 1))
      index += 2
    } else {
      positional.push(value)
      index += 1
    }
  }
  { positional, html, }
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
    Some(load_gerber(positional[3]))
  } else {
    None
  }
  let bottom = if positional.length() >= 5 {
    Some(load_gerber(positional[4]))
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
