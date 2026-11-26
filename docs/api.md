# 公共 API

在自己的 MoonBit 项目目录中运行 `moon add huahai29/moonplacement@0.2.0`，在可执行包的 `moon.pkg` 中导入：

```moonbit
import { "huahai29/moonplacement" @mp, }
pkgtype(kind: "executable")
```

把下面任一示例保存成这个包的 `main.mbt`，在该包目录运行 `moon run . --target js` 或 `moon run . --target wasm-gc`。输入已嵌入代码，可以直接运行。

- [两表对比](../examples/library/main.mbt.example)读取设计表和送厂表，调用 `audit` 并输出 D1 的位置差异。
- [拼板核对与复查](../examples/library/panel.mbt.example)读取两份表，直接解析顶层 Gerber 第 2 行第 2 列，再调用 `audit_checked`。D1 的位置有铜但缺少位号归属，示例从 `pad_evidence` 提取复查项。
- [点集配准](../examples/library/register.mbt.example)构造毫米坐标并选用刚体配准，求出从源点到目标点的 90° 旋转及平移。

三个示例均可从 Mooncakes 安装后运行。[独立安装验证](release-0.2.0.md)

| 要做什么 | 入口 |
| --- | --- |
| 读取两份坐标表和配置 | `read_placements(csv, source=...)`、`read_policy(json)`。无效输入抛出 `InputError` |
| 按配置读取原始坐标表 | 主分支提供 `read_placement_pair(baseline, delivery, policy, baseline_source=..., delivery_source=...)`。两张表和随后调用 `audit_checked` 应使用同一份 `Policy` |
| 读取铜层 | `parse_gerber(text, source=...)`。无效或不支持的输入抛出 `GerberError` |
| 只核对某个拼板单元 | 用 `parse_gerber_cell` 直接解析指定单元，或对已有整板文档调用 `select_panel_cell` |
| 比较坐标表并核验所传板面 | `audit(baseline, delivery, policy, top_gerber=Some(top), bottom_gerber=Some(bottom))`。可省略任一未提供的铜层 |
| 显式处理板面或铜层用途冲突 | `audit_checked` 调用方式与 `audit` 相同，遇到明确冲突时抛出带源文件名的 `InputError`。`audit` 会返回 `Indeterminate` 和 `invalid_gerber_layer` |
| 保存证据 | `AuditResult.report` 是 JSON v3；`render_html(result.report, baseline)` 返回可离线打开的 HTML 字符串 |
| 保存输入指纹 | `audit_receipt(result, inputs, host=..., build_sha256=...)` 把宿主计算的哈希与原报告写入[核验凭据](receipt.md) |
| 自己做点集配准 | 用 `Point::new(x, y)` 创建毫米坐标，再调用 `register(source, target, model, threshold_mm)`。模型为 `Rigid`、`Similarity` 或 `Affine`，返回从源点到目标点的变换及逐点残差 |

选择单元时，行列从 1 开始。双面核对先选顶层，再为底层传入同一单元的顶层文档作为 `reference`；两张坐标表都使用第一单元的坐标系。[拼板单元规则](audit.md#拼板单元)

通过 `AuditResult.verdict` 区分 `Pass`、`Different` 和 `Indeterminate`。遇到 `Indeterminate` 时，读 `reason`、`rejected_frames` 或 `pad_evidence` 定位缺失的证据。[JSON v3 字段说明](audit.md#json-报告-v3)

## 机器读取报告契约

[接口契约.json](接口契约.json)由 MoonBit 代码生成，可用 JSON Schema 2020-12 验证报告。它描述正常报告、输入错误、常用定位结构，并附退出码和文件字节上限。其余诊断语义见[核对规则](audit.md)。CLI 可用 `--report-schema` 输出同一份结构。
