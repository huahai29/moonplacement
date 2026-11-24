# 开源 PCB 拼板验收

使用 [jiegec 的 HT42B534USB2UART](https://github.com/jiegec/HT42B534USB2UART/tree/d2918ef58d9195c7c295e8515ccfccd5ef9b1b4b)。这是一块布好线的双层 USB 转串口板，有实际走线、过孔和铺铜。上游板与许可证见[验收资料](../examples/hardware/ht42b534/README.md)。

在 Linux（CI 为 Ubuntu 24.04）安装 KiCad 7 和系统 Python 的 `pcbnew` 模块，再在仓库根目录运行：

```sh
moon build --target js
node tests/kicad-panel.mjs
```

脚本用 KiCad 从原板生成 2×2 拼板（X 间隔 40 mm，Gerber Y 间隔 32 mm），然后分别导出原板和拼板的双面 Gerber 及位置表。两条路径分别验收：

| 路径 | 输入和核验范围 |
| --- | --- |
| KiCad 原生拼板 | 使用原生拼板导出文件，按每个单元的独立位号选出坐标表并核验。第 2 行第 2 列的 D1 对应 D3001 |
| 选择 SR 单元 | 在原生单板 Gerber 的绘图段外加 Gerber `SR`，保持原始光圈和铜层对象，用 `--panel-cell` 核验各单元 |

装配核验范围是 12 颗顶面器件（C1–C7、D1、R1–R3、U1），铜层输入保留整板线路。J1、J2、J3 接插件未纳入本次装配核验。原生拼板保留所有器件并导出双面铜层；普通 KiCad 拼板出口不一定生成 `SR`，第二条路径的 `SR` 封装由验收脚本添加。

正常组应在两条路径的四个单元都通过。故障组只改第 2 行第 2 列送厂坐标表中的 D1，铜层保持原样。原生拼板应报告 D3001，SR 路径应报告 D1 和单元行列。两张表采用同一错误坐标时，两表对比无差异，铜层核验仍能报出偏移。

脚本还把原生单板双面铜层的 SR 行列改成 10×10，核验第 10 行第 10 列。正常输入应通过。两表同错时，报告只在铜层中指出 D1 的偏移。[各案例报告的偏位量](acceptance-results.md#kicad-实板拼板)由测试生成。

输出位于 `_build/real-panel/`，含生成的拼板、原生 Gerber 和位置表、SR 输入、JSON 和 HTML 报告。汇总为 `acceptance.json`，CI 将它和原始输出一并保存。
