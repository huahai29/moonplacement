# 公共 API

在自己的 MoonBit 项目目录中运行 `moon add huahai29/moonplacement@0.1.1`，在可执行包的 `moon.pkg` 中导入：

```moonbit
import { "huahai29/moonplacement" @mp, }
pkgtype(kind: "executable")
```

把[完整示例](../examples/library/main.mbt.example)保存成这个包的 `main.mbt`，在该包目录运行 `moon run . --target js` 或 `moon run . --target wasm-gc`。示例直接传入两份表和配置，输出 `different`，指出 D1 的位置偏差约 0.30 mm。[独立安装验证](release-0.1.1.md)

| 要做什么 | 入口 |
| --- | --- |
| 读取两份坐标表和配置 | `read_placements(csv, source=...)`、`read_policy(json)`。无效输入抛出 `InputError` |
| 读取铜层 | `parse_gerber(text, source=...)`。无效或不支持的输入抛出 `GerberError` |
| 只核对某个拼板单元 | 对已有整板文档调用 `select_panel_cell`。GitHub 主分支还提供 `parse_gerber_cell`，可直接解析指定单元 |
| 比较坐标表并核验所传板面 | `audit(baseline, delivery, policy, top_gerber=Some(top), bottom_gerber=Some(bottom))`。可省略任一未提供的铜层 |
| 保存证据 | `AuditResult.report` 是 JSON v3；`render_html(result.report, baseline)` 返回可离线打开的 HTML 字符串 |
| 自己做点集配准 | `register` 支持刚体、相似和仿射模型，返回变换与基准点残差 |

选择单元时，行列从 1 开始。双面核对先选顶层，再为底层传入同一单元的顶层文档作为 `reference`；两张坐标表都使用第一单元的坐标系。[拼板单元规则](audit.md#拼板单元)

通过 `AuditResult.verdict` 区分 `Pass`、`Different` 和 `Indeterminate`。遇到 `Indeterminate` 时，读 `reason`、`rejected_frames` 或 `pad_evidence` 定位缺失的证据。[JSON v3 字段说明](audit.md#json-报告-v3)
