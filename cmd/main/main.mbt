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
extern "js" fn publish_html(filename : String, text : String) -> String =
  #| (filename, text) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   const paths = process.getBuiltinModule('node:path');
  #|   const basename = paths.basename(filename);
  #|   if (!basename || basename === '.' || basename === '..' ||
  #|       filename.endsWith('/') || (process.platform === 'win32' && filename.endsWith('\\'))) {
  #|     return '请指定新文件名';
  #|   }
  #|   let staging;
  #|   let temporary;
  #|   let failure = '';
  #|   try {
  #|     const parent = fs.realpathSync.native(paths.dirname(filename));
  #|     const target = paths.join(parent, basename);
  #|     staging = fs.mkdtempSync(paths.join(parent, '.moonplacement-'));
  #|     temporary = paths.join(staging, 'report.html');
  #|     fs.writeFileSync(temporary, text, { encoding: 'utf8', flag: 'wx', flush: true });
  #|     // Publish only after writing and closing the complete file. Linking
  #|     // creates the destination without replacing a racing directory entry.
  #|     fs.linkSync(temporary, target);
  #|   } catch (error) {
  #|     failure = error.code === 'EEXIST'
  #|       ? '目标已存在，请换一个新文件名 (EEXIST)'
  #|       : error.code ?? error.message;
  #|   } finally {
  #|     if (staging) {
  #|       try {
  #|         fs.rmSync(temporary, { force: true });
  #|         fs.rmdirSync(staging);
  #|       } catch {
  #|         const warning = '暂存目录清理失败：' + staging;
  #|         if (failure) failure += '。' + warning;
  #|         else console.error(warning);
  #|       }
  #|     }
  #|   }
  #|   return failure;
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
fn usage() -> String {
  "用法：moon run cmd/main --target js -- <基准.csv> <送厂.csv> <配置.json> [顶层.gbr] [底层.gbr] [--panel-cell 行,列] [--html 报告.html]\n       moon run cmd/main --target js -- --report-schema"
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
    if value == "--html" {
      if html is Some(_) ||
        index + 1 >= arg_count() ||
        arg(index + 1).is_empty() ||
        arg(index + 1).has_prefix("--") {
        raise @placement.InvalidInput(
          "html", "--html 需要且只能提供一次新报告文件名",
        )
      }
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
  let text = load_file(path, @placement.INPUT_FILE_MAX_BYTES)
  try {
    if cell is Some((row, column)) {
      @placement.parse_gerber_cell(text, row~, column~, source=path, reference?)
    } else {
      @placement.parse_gerber(text, source=path)
    }
  } catch {
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
  if arg_count() == 1 && arg(0) == "--report-schema" {
    println(@placement.report_contract().stringify(indent=2))
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
  let policy = @placement.read_policy(
    load_file(positional[2], @placement.POLICY_FILE_MAX_BYTES),
  )
  let baseline = @placement.read_placements(
    load_file(positional[0], @placement.INPUT_FILE_MAX_BYTES),
    source=positional[0],
  )
  let delivery = @placement.read_placements(
    load_file(positional[1], @placement.INPUT_FILE_MAX_BYTES),
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
      let error = publish_html(path, html)
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
  result.verdict.exit_code()
}

///|
fn main {
  let code = run() catch {
    @placement.InvalidInput(field, message) => {
      let report = @placement.input_error_report(field, message)
      println(report.stringify(indent=2))
      @placement.INPUT_ERROR_EXIT_CODE
    }
  }
  finish(code)
}
