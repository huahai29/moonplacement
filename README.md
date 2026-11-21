# MoonPlacement

[![MoonPlacement 检查](https://github.com/huahai29/moonplacement/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

PCB 送厂前，用 MoonPlacement 对照设计坐标表和送厂坐标表，找出漏件、多件、贴错面、偏位和角度差。手边有 Gerber 铜层的话，还能检查两张表是否把同一颗器件都标错了位置。

## 安装并运行

安装 [MoonBit](https://www.moonbitlang.com/download/) 和 Node.js 22.3 或更新版本。CI 使用 `moonc v0.10.16+b1a0e846e`。不用安装 npm 依赖。

```sh
git clone https://github.com/huahai29/moonplacement.git
cd moonplacement
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json
```

正常会输出 `"status": "pass"`。把送厂表换成 `examples/delivery-errors.csv`，可以看到 C7 漏件和 D1 错面。加上顶层铜文件和 `--html`，就能在浏览器里查看报告：

```sh
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/top-copper.gbr --html _build/report.html
```

## 核对自己的板子

1. 导出同一版 PCB 的设计表和送厂表，保存为 UTF-8 CSV。支持 KiCad 位置表和嘉立创 CPL 风格的列名。
2. 复制[示例配置](examples/policy.json)，填写单位、底面 X 和角度约定，选至少三颗位置分散且确认正确的器件作为对齐基准。自动判断底面 X 时，选一颗远离 X=0 的底面基准。
3. 运行上面的命令。核对铜层时，先传顶层、再传底层。Gerber 与设计坐标表须使用同一原点和坐标方向。

报告先看 `status`，再看 `differences`（两表差异）和 `pad_evidence`（铜层证据）。无法对齐时，查看 `frame.anchor_residuals` 或 `rejected_frames` 排查基准。焊盘归属来自 Gerber X2 位号；缺少归属时，附近有铜也不足以确认器件。非对称封装的贴装原点可能和铜形中心不同。

| 退出码 | 状态 | 含义 |
| --- | --- | --- |
| 0 | `pass` | 已完成所要求的核对，未发现差异 |
| 1 | `different` | 已确认差异 |
| 2 | `indeterminate` | 对齐或铜层证据不足，需复查 |
| 64 | `input_error` | 输入文件、参数或数据无效 |

## 可复现案例

- [KiCad 双面实导出](examples/README.md#铜层实导出验证)：两张表都把底面 C7 偏移了 0.30 mm。两表结果为 `pass`，加入原铜层后，报告指出 C7 的偏移。
- [块光圈与 PyGerber 对照](docs/gerber-acceptance.md#块光圈与独立对照)：核验展开前后的拼板几何，并对比 KiCad 实际导出铜层的采样点。
- [配置和报告字段](docs/audit.md) · [Gerber 2024.05 命令覆盖表](docs/gerber-acceptance.md#规范命令矩阵) · [CI 记录](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

解析、配准和判定由 MoonBit 实现。Gerber 2024.05 是兼容目标，当前覆盖以验收表为准。KiCad 和 PyGerber 只用于验证样例。

[MIT 许可证](LICENSE)
