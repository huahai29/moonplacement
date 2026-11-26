///|
extern "js" fn arg_count() -> Int32 = "() => process.argv.length - 2"

///|
extern "js" fn arg(index : Int32) -> String = "(index) => process.argv[index + 2]"

///|
extern "js" fn finish(code : Int32) -> Unit = "(code) => { process.exitCode = code; }"

///|
type FileRead

///|
extern "js" fn read_file(
  path : String,
  limit : Int32,
  fingerprint : Bool,
) -> FileRead =
  #| (path, limit, fingerprint) => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     const fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
  #|     try {
  #|       const start = fs.fstatSync(fd, { bigint: true });
  #|       if (!start.isFile()) return { error: "需要普通文件" };
  #|       const bytes = Buffer.alloc(limit + 1);
  #|       let length = 0;
  #|       while (length < bytes.length) {
  #|         const count = fs.readSync(fd, bytes, length, bytes.length - length, null);
  #|         if (!count) break;
  #|         length += count;
  #|       }
  #|       if (length > limit) return { error: "文件超过 " + limit + " 字节" };
  #|       const snapshot = bytes.subarray(0, length);
  #|       let sha256 = '';
  #|       if (fingerprint) {
  #|         const after = fs.fstatSync(fd, { bigint: true });
  #|         if (start.size !== BigInt(length) || start.size !== after.size ||
  #|             start.mtimeNs !== after.mtimeNs || start.ctimeNs !== after.ctimeNs) {
  #|           return { error: '文件在读取期间发生变化，请重试' };
  #|         }
  #|         sha256 = process.getBuiltinModule('node:crypto').createHash('sha256').update(snapshot).digest('hex');
  #|       }
  #|       return { text: new TextDecoder('utf-8', { fatal: true }).decode(snapshot), length, sha256 };
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
extern "js" fn file_length(file : FileRead) -> Int32 = "(file) => file.length"

///|
extern "js" fn file_sha256(file : FileRead) -> String = "(file) => file.sha256"

///|
extern "js" fn cli_sha256() -> String =
  #| () => {
  #|   try {
  #|     const fs = process.getBuiltinModule('node:fs');
  #|     const bytes = fs.readFileSync(process.argv[1]);
  #|     return process.getBuiltinModule('node:crypto').createHash('sha256').update(bytes).digest('hex');
  #|   } catch {
  #|     return '';
  #|   }
  #| }

///|
extern "js" fn same_output(left : String, right : String) -> Bool =
  #| (left, right) => {
  #|   const fs = process.getBuiltinModule('node:fs');
  #|   const paths = process.getBuiltinModule('node:path');
  #|   const key = name => {
  #|     let path;
  #|     try { path = paths.join(fs.realpathSync.native(paths.dirname(name)), paths.basename(name)); }
  #|     catch { path = paths.resolve(name); }
  #|     return process.platform === 'win32' ? path.toLowerCase() : path;
  #|   };
  #|   return key(left) === key(right);
  #| }

///|
extern "js" fn publish_file(filename : String, text : String) -> String =
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
  #|     temporary = paths.join(staging, 'output');
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
  role : String,
  fingerprints : Array[@placement.ReceiptInput]?,
) -> String raise @placement.InputError {
  let file = read_file(path, limit, fingerprints is Some(_))
  let error = file_error(file)
  if !error.is_empty() {
    raise @placement.InvalidInput(path, error)
  }
  if fingerprints is Some(inputs) {
    inputs.push({
      role,
      byte_count: file_length(file),
      sha256: file_sha256(file),
    })
  }
  file_text(file)
}

///|
fn usage() -> String {
  "用法：moon run cmd/main --target js -- <基准.csv> <送厂.csv> <配置.json> [顶层.gbr] [底层.gbr] [--panel-cell 行,列] [--html 报告.html] [--receipt 凭据.json]\n       moon run cmd/main --target js -- --report-schema"
}

///|
priv struct CliArgs {
  positional : Array[String]
  html : String?
  receipt : String?
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
  let mut receipt : String? = None
  let mut cell = None
  let mut index = 0
  while index < arg_count() {
    let value = arg(index)
    if value == "--html" || value == "--receipt" {
      let is_html = value == "--html"
      let previous = if is_html { html } else { receipt }
      if previous is Some(_) ||
        index + 1 >= arg_count() ||
        arg(index + 1).is_empty() ||
        arg(index + 1).has_prefix("--") {
        raise @placement.InvalidInput(
          if is_html {
            "html"
          } else {
            "receipt"
          },
          "\{value} 需要且只能提供一次新输出文件名",
        )
      }
      if is_html {
        html = Some(arg(index + 1))
      } else {
        receipt = Some(arg(index + 1))
      }
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
  { positional, html, receipt, cell, }
}

///|
fn load_layer(
  path : String,
  cell : (Int32, Int32)?,
  role : String,
  fingerprints : Array[@placement.ReceiptInput]?,
) -> @placement.GerberDocument raise @placement.InputError {
  let text = load_file(
    path,
    @placement.INPUT_FILE_MAX_BYTES,
    role,
    fingerprints,
  )
  try {
    if cell is Some((row, column)) {
      @placement.parse_gerber_cell(text, row~, column~, source=path)
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
  if args.html is Some(html) &&
    args.receipt is Some(receipt) &&
    same_output(html, receipt) {
    raise @placement.InvalidInput(
      receipt, "报告和凭据需要不同的输出路径",
    )
  }
  let fingerprints = if args.receipt is Some(_) { Some([]) } else { None }
  let policy = @placement.read_policy(
    load_file(
      positional[2],
      @placement.POLICY_FILE_MAX_BYTES,
      "policy",
      fingerprints,
    ),
  )
  let (baseline, delivery) = @placement.read_placement_pair(
    load_file(
      positional[0],
      @placement.INPUT_FILE_MAX_BYTES,
      "baseline",
      fingerprints,
    ),
    load_file(
      positional[1],
      @placement.INPUT_FILE_MAX_BYTES,
      "delivery",
      fingerprints,
    ),
    policy,
    baseline_source=positional[0],
    delivery_source=positional[1],
  )
  let result = if positional.length() == 5 {
    @placement.audit_gerber_pair(
      baseline,
      delivery,
      policy,
      load_file(
        positional[3],
        @placement.INPUT_FILE_MAX_BYTES,
        "top_gerber",
        fingerprints,
      ),
      load_file(
        positional[4],
        @placement.INPUT_FILE_MAX_BYTES,
        "bottom_gerber",
        fingerprints,
      ),
      top_source=positional[3],
      bottom_source=positional[4],
      cell?=args.cell,
    )
  } else {
    let top = if positional.length() == 4 {
      Some(load_layer(positional[3], args.cell, "top_gerber", fingerprints))
    } else {
      None
    }
    @placement.audit_checked(baseline, delivery, policy, top_gerber=top)
  }
  if args.receipt is Some(path) && fingerprints is Some(inputs) {
    let build_sha256 = cli_sha256()
    if build_sha256.is_empty() {
      raise @placement.InvalidInput(path, "无法计算 CLI 构建的 SHA-256")
    }
    let receipt = @placement.audit_receipt(
      result,
      inputs,
      host="cli",
      build_sha256~,
    )
    let error = publish_file(path, receipt.stringify(indent=2) + "\n")
    if !error.is_empty() {
      raise @placement.InvalidInput(path, "无法写入核验凭据：\{error}")
    }
  }
  match args.html {
    Some(path) => {
      let html = @placement.render_html(result.report, baseline)
      let error = publish_file(path, html)
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
