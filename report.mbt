///|
fn json_get(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn json_string(value : Json, key : String) -> String {
  match json_get(value, key) {
    Some(String(text)) => text
    _ => ""
  }
}

///|
fn json_double(value : Json, key : String) -> Double {
  match json_get(value, key) {
    Some(Number(number, ..)) => number
    _ => 0.0
  }
}

///|
fn json_int(value : Json, key : String) -> Int32 {
  json_double(value, key).to_int()
}

///|
fn json_array(value : Json, key : String) -> Array[Json] {
  match json_get(value, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn escape_html(text : String) -> String {
  let builder = StringBuilder()
  for _, ch in text.iter2() {
    match ch {
      '<' => builder.write_string("&lt;")
      '>' => builder.write_string("&gt;")
      '&' => builder.write_string("&amp;")
      '"' => builder.write_string("&quot;")
      _ => builder.write_char(ch)
    }
  }
  builder.to_string()
}

///|
fn marker_color(
  reference : String,
  problems : Map[String, Bool],
  pads : Map[String, Bool],
) -> String {
  if pads.contains(reference) {
    "#e8890c"
  } else if problems.contains(reference) {
    "#d22b2b"
  } else {
    "#2f9e44"
  }
}

///|
fn difference_detail(item : Json) -> String {
  match json_string(item, "kind") {
    "position" | "pad_offset" =>
      "<span>距离 \{json_double(item, "distance_mm")} mm</span>"
    "angle" => "<span>角度差 \{json_double(item, "delta_deg")}°</span>"
    "side" =>
      "<span>基准 \{escape_html(json_string(item, "baseline"))} / 送厂 \{escape_html(json_string(item, "delivery"))}</span>"
    "value" | "package" =>
      "<span>基准 \{escape_html(json_string(item, "baseline"))} / 送厂 \{escape_html(json_string(item, "delivery"))}</span>"
    _ => "—"
  }
}

///|
fn difference_row(item : Json) -> String {
  let reference = escape_html(json_string(item, "ref"))
  let kind = escape_html(json_string(item, "kind"))
  "<tr><td>\{reference}</td><td>\{kind}</td><td>\{difference_detail(item)}</td></tr>"
}

///|
fn differences_table(items : Array[Json]) -> String {
  if items.length() == 0 {
    return "<p>无</p>"
  }
  let builder = StringBuilder()
  builder.write_string(
    "<table><tr><th>位号</th><th>类型</th><th>详情</th></tr>",
  )
  for item in items {
    builder.write_string(difference_row(item))
  }
  builder.write_string("</table>")
  builder.to_string()
}

///|
/// Render a self-contained HTML report. The board map uses the trusted baseline
/// positions and draws a red arrow for every reported position offset.
pub fn render_html(report : Json, baseline : PlacementTable) -> String {
  let status = json_string(report, "status")
  let reason = json_string(report, "reason")
  let differences = json_array(report, "differences")
  let pad_differences = json_array(report, "pad_differences")
  let pad_evidence = json_array(report, "pad_evidence")
  let pad_state = match json_string(report, "pad_status") {
    "complete" => "已取得全部位号证据"
    "incomplete" => "部分器件缺少位号证据"
    "skipped" => "未能对齐，未核验"
    _ => "未提供铜层"
  }
  let problems : Map[String, Bool] = Map([])
  for item in differences {
    problems[json_string(item, "ref")] = true
  }
  let pads : Map[String, Bool] = Map([])
  for item in pad_differences {
    pads[json_string(item, "ref")] = true
  }
  let rows = baseline.rows
  let mut min_x = 1.0e9
  let mut max_x = -1.0e9
  let mut min_y = 1.0e9
  let mut max_y = -1.0e9
  for part in rows.values() {
    min_x = min_x.min(part.xy.x)
    max_x = max_x.max(part.xy.x)
    min_y = min_y.min(part.xy.y)
    max_y = max_y.max(part.xy.y)
  }
  if min_x > max_x {
    min_x = 0.0
    max_x = 10.0
    min_y = 0.0
    max_y = 10.0
  }
  let width = 640.0
  let height = 480.0
  let padding = 50.0
  let span_x = (max_x - min_x).max(1.0)
  let span_y = (max_y - min_y).max(1.0)
  let scale = ((width - 2.0 * padding) / span_x).min(
    (height - 2.0 * padding) / span_y,
  )
  let svg = StringBuilder()
  svg.write_string(
    "<svg viewBox=\"0 0 640 480\" xmlns=\"http://www.w3.org/2000/svg\">",
  )
  svg.write_string(
    "<defs><marker id=\"arrow\" markerWidth=\"6\" markerHeight=\"6\" refX=\"5\" refY=\"3\" orient=\"auto\"><path d=\"M0,0 L6,3 L0,6 Z\" fill=\"#d22b2b\"/></marker></defs>",
  )
  svg.write_string(
    "<rect x=\"0\" y=\"0\" width=\"640\" height=\"480\" fill=\"#fafafa\" stroke=\"#dddddd\"/>",
  )
  for part in rows.values() {
    let cx = padding + (part.xy.x - min_x) * scale
    let cy = height - padding - (part.xy.y - min_y) * scale
    let color = marker_color(part.refdes, problems, pads)
    svg.write_string(
      "<circle cx=\"\{cx}\" cy=\"\{cy}\" r=\"5\" fill=\"\{color}\"/>",
    )
    svg.write_string(
      "<text x=\"\{cx + 8.0}\" y=\"\{cy + 4.0}\" font-size=\"10\" fill=\"#333333\">\{escape_html(part.refdes)}</text>",
    )
  }
  for item in differences {
    if json_string(item, "kind") == "position" {
      let reference = json_string(item, "ref")
      match rows.get(reference) {
        Some(part) => {
          let dx = json_double(item, "delta_x_mm")
          let dy = json_double(item, "delta_y_mm")
          let x1 = padding + (part.xy.x - min_x) * scale
          let y1 = height - padding - (part.xy.y - min_y) * scale
          let x2 = padding + (part.xy.x + dx - min_x) * scale
          let y2 = height - padding - (part.xy.y + dy - min_y) * scale
          svg.write_string(
            "<line x1=\"\{x1}\" y1=\"\{y1}\" x2=\"\{x2}\" y2=\"\{y2}\" stroke=\"#d22b2b\" stroke-width=\"1.5\" marker-end=\"url(#arrow)\"/>",
          )
        }
        None => ()
      }
    }
  }
  svg.write_string("</svg>")
  let reason_text = if reason.is_empty() {
    ""
  } else {
    "（" + escape_html(reason) + "）"
  }
  let html = StringBuilder()
  html.write_string(
    "<!DOCTYPE html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\"><title>MoonPlacement 报告</title>",
  )
  html.write_string(
    "<style>body{font-family:system-ui,-apple-system,sans-serif;margin:24px;color:#222}table{border-collapse:collapse;margin:12px 0}td,th{border:1px solid #dddddd;padding:4px 8px;font-size:13px;text-align:left}pre{background:#f5f5f5;padding:12px;overflow:auto;font-size:12px}</style>",
  )
  html.write_string("</head><body>")
  html.write_string("<h1>MoonPlacement 核对报告</h1>")
  html.write_string(
    "<p>状态：<b>\{escape_html(status)}</b>\{reason_text}</p>",
  )
  html.write_string(
    "<p>基准器件 \{json_int(report, "baseline_count")} 个 · 送厂器件 \{json_int(report, "delivery_count")} 个</p>",
  )
  html.write_string(svg.to_string())
  html.write_string(
    "<p style=\"font-size:12px;color:#666\">绿：一致，红：器件差异，橙：铜层差异；红箭头表示位置偏差。</p>",
  )
  html.write_string("<h2>器件差异</h2>")
  html.write_string(differences_table(differences))
  html.write_string("<h2>铜层核对</h2>")
  html.write_string(
    "<p>\{pad_state}：按位号核验 \{json_int(report, "pad_checked")} / \{pad_evidence.length()}。</p>",
  )
  html.write_string(differences_table(pad_differences))
  let mut listed_incomplete = false
  for item in pad_evidence {
    if json_get(item, "evidence") is Some(evidence) {
      let description = match json_string(evidence, "status") {
        "copper_only" => "附近有铜，位号归属未知"
        "unverified" =>
          match json_string(evidence, "reason") {
            "repeated_reference" =>
              "拼板中位号重复，请按单元拆分后核验"
            "possible_clearance" =>
              "焊盘可能受后绘制的清除对象影响"
            _ => "缺少可用的焊盘证据"
          }
        _ => continue
      }
      if !listed_incomplete {
        html.write_string("<ul>")
        listed_incomplete = true
      }
      let reference = escape_html(json_string(item, "ref"))
      let side = if json_string(item, "side") == "top" {
        "顶面"
      } else {
        "底面"
      }
      html.write_string("<li>\{reference}（\{side}）：\{description}</li>")
    }
  }
  if listed_incomplete {
    html.write_string("</ul>")
  }
  html.write_string("<h2>原始 JSON</h2>")
  html.write_string("<pre>\{escape_html(report.stringify(indent=2))}</pre>")
  html.write_string("</body></html>")
  html.to_string()
}
