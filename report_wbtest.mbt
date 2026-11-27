///|
test "offline report renders an offset and escapes the designator" {
  let baseline = fixture_table(
    "R1,1,1,0,top\nR2,4,1,0,top\nR3,1,4,0,top\nD<&>,4,4,0,top",
  )
  let delivery = fixture_table(
    "R1,1,1,0,top\nR2,4,1,0,top\nR3,1,4,0,top\nD<&>,4.3,4,0,top",
  )
  let result = audit(baseline, delivery, matching_policy())
  assert_true(result.verdict is Different)
  let html = render_html(result.report, baseline)
  assert_true(html.contains("D&lt;&amp;&gt;"))
  assert_false(html.contains("D<&>"))
  assert_true(html.contains("marker-end=\"url(#arrow)\""))
}

///|
test "HTML escapes all five special characters and preserves ordinary text" {
  assert_eq(
    escape_html("J1 <底铜> & \"A'B\""),
    "J1 &lt;底铜&gt; &amp; &quot;A&#39;B&quot;",
  )
  assert_eq(escape_html(""), "")
}

///|
fn empty_report_board() -> PlacementTable raise InputError {
  read_placement_table(
    "Ref,PosX,PosY,Rot,Side\n",
    "empty",
    default_table_import(),
    allow_empty=true,
  )
}

///|
test "online preview caps repeated findings and long text while full HTML retains them" {
  let board = empty_report_board()
  let findings : Array[Json] = []
  let reviews : Array[Json] = []
  let excluded : Array[String] = []
  for index in 0..<40 {
    excluded.push("X\{index}")
    findings.push({
      "ref": Json("P\{index}"),
      "kind": Json("package"),
      "baseline": Json("<".repeat(90) + "END"),
      "delivery": Json("new"),
    })
    reviews.push({
      "ref": Json("Q\{index}"),
      "side": Json("top"),
      "evidence": { "status": Json("unverified") },
    })
  }
  let report : Json = {
    "status": Json("different"),
    "pad_status": Json("incomplete"),
    "baseline_count": Json(161),
    "differences": Json(findings),
    "pad_evidence": Json(reviews),
    "placement_import": {
      "scope": Json("excluded"),
      "baseline": { "excluded_refs": Json(excluded) },
    },
  }
  let preview = render_html_preview(report, board)
  assert_true(preview.contains("仅显示前 32 项（共 40 项）。"))
  assert_true(preview.contains("未核对位号 X0"))
  assert_false(preview.contains("X39"))
  assert_true(preview.contains("P31"))
  assert_false(preview.contains("P32"))
  assert_true(preview.contains("Q31"))
  assert_false(preview.contains("Q32"))
  assert_true(preview.contains("&lt;…"))
  assert_false(preview.contains("END"))
  assert_false(preview.contains("<svg"))
  assert_false(preview.contains("<h2>原始 JSON</h2>"))
  let html = render_html(report, board)
  assert_true(html.contains("P39"))
  assert_true(html.contains("END"))
  assert_true(html.contains("<h2>原始 JSON</h2>"))
}

///|
test "library HTML uses the recorded baseline convention for bottom markers" {
  let baseline = fixture_table(
    "R1,0,0,0,top\nR2,2,0,0,top\nR3,-1,2,0,bottom\nU3,1,1,0,top",
  )
  let delivery = fixture_table(
    "R1,0,0,0,top\nR2,2,0,0,top\nR3,-1,2,0,bottom\nU3,1.1,1,0,top",
  )
  let defaults = matching_policy()
  let convention = { ..defaults.baseline, units: Inches, bottom_x: Negated, }
  let result = audit(baseline, delivery, {
    ..defaults,
    baseline: convention,
    delivery: convention,
  })
  assert_true(result.verdict is Different)
  assert_true(
    result.report
    is {
      "baseline_coordinates": {
        "unit": String("in"),
        "bottom_x": String("negated"),
        ..
      },
      ..
    },
  )
  let html = render_html(result.report, baseline)
  assert_true(
    html.contains(
      "<circle cx=\"240\" cy=\"50\" r=\"5\" fill=\"#2f9e44\"/><text",
    ),
  )
  assert_true(html.contains("<line x1=\"240\" y1=\"240\""))
}

///|
test "empty board and unchanged large coordinates render a finite board map" {
  let empty = empty_report_board()
  let empty_html = render_html(
    audit(empty, empty, matching_policy()).report,
    empty,
  )
  assert_true(empty_html.contains("<svg viewBox=\"0 0 640 480\""))
  assert_true(empty_html.contains("基准器件 0 个 · 送厂器件 0 个"))
  assert_false(empty_html.contains("<circle"))

  let board = fixture_table(
    "R1,-1000000,-1000000,0,top\nR2,1000000,-1000000,0,top\nR3,-1000000,1000000,0,top\nD1,1000000,1000000,0,top",
  )
  let unchanged = audit(board, board, matching_policy())
  assert_true(unchanged.verdict is Pass)
  let html = render_html(unchanged.report, board)
  assert_true(html.contains("<h2>器件差异</h2><p>无</p>"))
  assert_true(html.contains("未提供铜层：按位号核验 0 / 0"))
  assert_true(html.contains("<circle cx=\"50\" cy=\"430\""))
  assert_true(html.contains("<circle cx=\"430\" cy=\"50\""))
  assert_false(html.contains("NaN"))
  assert_false(html.contains("Infinity"))
  assert_false(html.contains("<line "))
}

///|
test "layer failure shows the parser message beside a completed copper check" {
  let board = empty_report_board()
  let report : Json = {
    "status": Json("indeterminate"),
    "reason": Json("incomplete_gerber_layers"),
    "pad_status": Json("incomplete"),
    "pad_checked": Json(1),
    "pad_layers": [
      {
        "side": Json("top"),
        "status": Json("failed"),
        "checked": Json(0),
        "targets": Json(0),
        "message": Json("无法解析 <宏's名>"),
      },
      {
        "side": Json("bottom"),
        "status": Json("complete"),
        "checked": Json(1),
        "targets": Json(1),
      },
    ],
    "pad_evidence": [
      {
        "ref": Json("J1"),
        "side": Json("bottom"),
        "evidence": { "status": Json("by_reference") },
      },
    ],
  }
  let html = render_html(report, board)
  assert_true(
    html.contains(
      "<li>顶铜核验失败 · 无法解析 &lt;宏&#39;s名&gt;</li>",
    ),
  )
  assert_true(html.contains("<li>底铜已核验全部位号（1 / 1）</li>"))
  assert_true(
    html.contains("部分铜层未完成核验：按位号核验 1 / 1"),
  )
  assert_false(html.contains("<宏's名>"))
  assert_false(html.contains("（0 / 0）"))
}

///|
test "HTML distinguishes corrected origins from review and pose mismatch" {
  let board = empty_report_board()
  let report : Json = {
    "pad_status": Json("incomplete"),
    "pad_checked": Json(1),
    "pad_evidence": [
      {
        "ref": Json("J1"),
        "side": Json("bottom"),
        "evidence": {
          "status": Json("by_reference"),
          "distance_mm": Json(0.000000001),
          "origin": {
            "status": Json("corrected"),
            "raw_distance_mm": Json(2.25),
            "source": Json("PCB"),
          },
        },
      },
      {
        "ref": Json("J2"),
        "side": Json("top"),
        "evidence": {
          "status": Json("unverified"),
          "reason": Json("pad_origin_review"),
          "origin": {
            "status": Json("review"),
            "raw_distance_mm": Json(1.5),
            "source": Json("核对 <J2>"),
          },
        },
      },
      {
        "ref": Json("J3"),
        "side": Json("bottom"),
        "evidence": {
          "status": Json("unverified"),
          "reason": Json("pad_origin_review"),
          "origin": {
            "status": Json("pose_mismatch"),
            "raw_distance_mm": Json(1.25),
            "source": Json("板 A"),
          },
        },
      },
    ],
  }
  let html = render_html(report, board)
  assert_true(
    html.contains(
      "部分器件的铜层证据需复查：按位号核验 1 / 3",
    ),
  )
  assert_true(
    html.contains(
      "J1（底面）：原点偏移已校正。原始距离 2.25 mm，校正后 0 mm。依据：PCB",
    ),
  )
  assert_true(
    html.contains(
      "J2（顶面）：需复查：原始距离 1.5 mm。原因：核对 &lt;J2&gt;",
    ),
  )
  assert_true(
    html.contains(
      "J3（底面）：需复查：板面或基准角度与校正规则不符，原始距离 1.25 mm。依据：板 A",
    ),
  )
}

///|
test "skipped copper checks explain invalid inputs and unresolved alignment" {
  let board = empty_report_board()
  for
    (reason, message) in [
      ("invalid_gerber_layer", "Gerber 板面或用途不符，未核验"),
      ("incomplete_gerber_layers", "铜层输入有误，未核验"),
      ("ambiguous_frame", "未能对齐，未核验"),
    ] {
    let report : Json = {
      "status": Json("indeterminate"),
      "reason": Json(reason),
      "pad_status": Json("skipped"),
      "pad_layers": [
        {
          "side": Json("bottom"),
          "status": Json("skipped"),
          "checked": Json(0),
          "targets": Json(0),
        },
      ],
    }
    let html = render_html(report, board)
    assert_true(html.contains("\{message}：按位号核验 0 / 0"))
    assert_true(html.contains("<li>底铜无法完成配准，未核验</li>"))
  }
}

///|
test "clearance explanation locates the object and works with partial evidence" {
  let clearance : Json = {
    "clearance": {
      "pad": { "pin": Json("A'1"), "x_mm": Json(30), "y_mm": Json(10) },
      "object": {
        "kind": Json("arc"),
        "object_number": Json(15),
        "statement_number": Json(32),
      },
    },
  }
  assert_eq(
    clearance_description(clearance),
    "焊盘可能受后绘制的清除对象影响。引脚 A&#39;1 中心 (30, 10) mm；清除圆弧 #15（Gerber 命令 #32）。",
  )
  assert_eq(
    clearance_description({}),
    "焊盘可能受后绘制的清除对象影响",
  )
}
