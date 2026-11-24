# 验收结果摘要

这里集中记录文档引用的样例结论。结果表使用 CLI 报告和验收门槛生成，CI 会重新执行案例并核对表中的内容。

## 内置 Gerber 样例

<!-- builtin-results:start -->

| 案例 | 结论 |
| --- | --- |
| 2×2 拼板的第 2 行、第 2 列 | 两表为 `pass`，加入铜层后为 `different`。D1 偏移 0.30 mm |
| 变换双孔宏 | `pass`。D1 的铜形几何中心偏离约 0.060 mm，仍在 0.1 mm 容差内 |

<!-- builtin-results:end -->

运行 `node tests/demo-report.mjs` 复核。[输入与命令](../examples/README.md#核对拼板单元)

## KiCad 双面实导出

<!-- kicad-export-results:start -->

| 案例 | 结论 |
| --- | --- |
| 两种底面 X 约定 | `pass`，按位号核验 6 颗。U3 圆角宏和 R2 切角轮廓宏的中心偏差均小于 0.001 mm |
| 只移动送厂表的 C7 | `different`，铜层检出 C7 偏移 0.30 mm |
| 同时移动两张表的 C7 | 两表为 `pass`，加入双面铜层后为 `different`。唯一铜层偏位为 C7，0.30 mm |

<!-- kicad-export-results:end -->

[双面样例的复现步骤](../examples/README.md#铜层实导出验证)

## KiCad 实板拼板

<!-- kicad-panel-results:start -->

| 案例 | 结论 |
| --- | --- |
| 2×2 原生拼板，第 2 行、第 2 列 | `different`，报告定位到 D3001，铜层偏差 0.30 mm |
| 2×2 SR 拼板，第 2 行、第 2 列，两表同错 | `different`，两表无差异，铜层检出 D1 偏移 0.30 mm |
| 10×10 SR 拼板，第 10 行、第 10 列，两表同错 | `different`，两表无差异，铜层检出 D1 偏移 0.30 mm |

<!-- kicad-panel-results:end -->

[实板与拼板的复现步骤](real-panel.md)
