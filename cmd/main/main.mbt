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
  "用法：moon run cmd/main --target js -- <基准.csv> <送厂.csv> <配置.json>"
}

///|
fn run() -> Int32 raise @placement.InputError {
  if arg_count() == 1 && (arg(0) == "--help" || arg(0) == "-h") {
    println(usage())
    return 0
  }
  if arg_count() != 3 {
    raise @placement.InvalidInput("arguments", usage())
  }
  let policy = @placement.read_policy(load_file(arg(2), 65_536))
  let baseline = @placement.read_placements(
    load_file(arg(0), 8_388_608),
    source=arg(0),
  )
  let delivery = @placement.read_placements(
    load_file(arg(1), 8_388_608),
    source=arg(1),
  )
  let result = @placement.audit(baseline, delivery, policy)
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
