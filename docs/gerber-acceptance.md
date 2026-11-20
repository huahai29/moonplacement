# Gerber 2024.05 验收

## 完整格式支持目标

完整读取并求值 **Ucamco Gerber Layer Format Specification 2024.05 的现行图层文件**，从标准命令重建图形及其属性，再为双面 PCB 装配核验提供可追溯的焊盘证据。目标按规范第 2.8 节命令表、第 3 至 5 章语法与语义以及第 2.12 节的读取器要求验收。第 8 章废弃命令单列兼容情况。Gerber Job、钻孔文件和 Gerber 写出另行定义。[Ucamco 2024.05 规范](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf)

铜层读取、光圈几何、坐标配准、位号关联、证据判定和报告由 MoonBit 实现。Node.js 提供命令行宿主。KiCad 用于生成独立测试输入，运行核验只需已有的 CSV、配置和 Gerber 文件。

## 规范命令矩阵

分母取自 **2024.05 版 §2.8 的 26 行**。`G36` 和 `G37` 各计一行，`AB` 和 `SR` 分别按开、闭合计一行。当前 **已实现 11 / 26，部分处理 13 / 26，拒收 2 / 26**。「已实现」指命令的当前用法已有可检查结果。部分处理的命令即使通过个别示例，也仍计入部分处理。[规范 §2.8，印刷页 19](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf#page=19)

| 命令 | 状态 | 测试或样例 | 失败或剩余边界 |
| --- | --- | --- | --- |
| `G04` | 已实现 | 单测「trailing zero omission」内含疑似指令的注释 | 注释正文不改变绘图状态 |
| `MO` | 已实现 | 单测「inch units scale」 | 缺失或不支持的单位报输入错误 |
| `FS` | 已实现 | CLI「normalizes supported Gerber coordinates」 | 增量、不匹配的轴位宽和超宽坐标报输入错误 |
| `AD` | 部分处理 | 单测「standard apertures subtract a concentric round hole」、D1 圆孔对照 | 标准 `C/R/O/P` 支持实心和同心圆孔。零直径孔、碰到外边界的孔，以及仍不支持的模板报输入错误 |
| `AM` | 部分处理 | MoonBit 单测「off-center clearance」、D1 圆孔对照、KiCad U3 实导出 | 支持单个实心圆（1）或中心线矩形（21）内开一个圆孔、KiCad 的圆角轮廓组合（4、1、20）及数值表达式。跨边界切除、多个清除图元或其他组合报输入错误 |
| `Dnn` | 已实现 | 单测「parses flashes」在两种光圈间切换 | 使用未定义光圈绘图时报输入错误 |
| `D01` | 部分处理 | 单测「regions become filled polygons」、CLI 圆弧回归 | 直线保留图形。圆弧使用保守包围。非法光圈或缺失起点报输入错误 |
| `D02` | 已实现 | 单测「trailing zero omission」 | 未建立当前位置时须提供两轴坐标 |
| `D03` | 已实现 | 三个 D1 案例、单测「macro rotation」 | 继承模态坐标。缺少位置或光圈报输入错误 |
| `G01` | 已实现 | CLI 核验直线区域与位号证据的回归文件 | 后续 D01 进入直线模式 |
| `G02` | 部分处理 | CLI「keeps unrelated flash evidence」顺时针案例 | 保守包围并警告。缺少有效 I/J 报输入错误 |
| `G03` | 部分处理 | 同一 CLI 回归的逆时针和清除圆弧案例 | 保守包围并警告。影响范围内的位号标为未核验 |
| `G75` | 部分处理 | 同一 CLI 回归显式声明 G75 | 读取多象限声明。精确圆弧及其状态校验待完成 |
| `LP` | 部分处理 | CLI 清除在闪光前、在闪光后及位于远处的对照 | 按绘制先后和保守包围筛选受影响位号，完整布尔合成待完成 |
| `LM` | 已实现 | D1 偏心宏及单测「macro rotation」 | 识别 N/X/Y/XY。未知模式报输入错误 |
| `LR` | 已实现 | D1 偏心宏及单测「macro rotation」 | 按原始光圈应用旋转，非法角度报输入错误 |
| `LS` | 已实现 | D1 双焊盘面积加权案例及通过对照 | 按原始光圈缩放，非正或不可计算比例报输入错误 |
| `G36` | 部分处理 | 单测「regions become filled polygons」及含弧区域回归 | 单轮廓可读取，多轮廓报输入错误 |
| `G37` | 部分处理 | 同一单轮廓与含弧区域回归 | 结束单轮廓，文件结束时未关区域报输入错误 |
| `AB` | 拒收 | CLI「rejects Gerber commands」块光圈案例 | 直接报输入错误 |
| `SR` | 拒收 | 同一 CLI 回归的步进重复案例 | 直接报输入错误 |
| `TF` | 部分处理 | D1 样例包含 `.FileFunction` | 完整文件属性保留待完成，负像文件报输入错误 |
| `TA` | 部分处理 | KiCad 双面实导出携带光圈属性 | 识别命令，当前未保留到对象。完整作用域待完成 |
| `TO` | 部分处理 | 单测「TO.P supplies the owner」 | 提取 `.P/.C`，其他对象属性的保留待完成 |
| `TD` | 部分处理 | 同一单测检查按名清除和清空 | 支持当前位号属性。完整属性字典待完成 |
| `M02` | 已实现 | 单测「trailing zero omission」检查终止 | 终止读取。兼容无终止符的旧输入 |

测试入口：[MoonBit 单测](../gerber_wbtest.mbt) · [CLI 回归](../tests/cli.test.mjs) · [KiCad 实导出](../examples/README.md#铜层实导出验证)。

发布门槛以规范 §2.12 的合规读取要求和第 3 至 5 章语义为准。按 §2.8 逐项补足后，还需将合法公开文件的几何与独立 Gerber 实现对照，校验宏、变换、极性、重复的组合及属性归属。上述矩阵用于记录进度，发布证据还应给出对照所用文件、工具版本和差异阈值。

圆弧诊断与逐位号证据独立。后绘制的清除对象可能与某个焊盘相交时，该器件标为 `unverified`，原因是 `possible_clearance`，其余器件照常核验。保守包围可能把部分未实际相交的焊盘列为待复查。报告保留已确认的差异。超出当前可处理范围的几何命令报输入错误。

## 输入、命令和实测输出

三组用例沿用同一份设计表、送厂表和配置，只更换顶层铜层。也可先复跑 [KiCad 双面实导出案例](../examples/README.md#铜层实导出验证)，查看顶面 U3 倾斜的圆角焊盘，以及 C7 在两张表同时偏移时如何由铜层检出。U3 的通过条件是实导出中确有 `RoundRect` 定义和调用，报告按 U3 位号找到一块铜且中心偏差小于 0.001 mm。MoonBit 单测另用可独立计算的几何对照验证合成面积、铜形几何中心、外部变换和圆角边界。

```sh
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/gerber/pad-scaled.gbr
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/gerber/macro-transformed.gbr
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/gerber/macro-transformed-pass.gbr
```

| 输入 | 独立计算 | CLI 结果 |
| --- | --- | --- |
| [缩放焊盘](../examples/gerber/pad-scaled.gbr) | 第二个闪光面积是第一个的 4 倍，加权中心为 `(24, 13.6) mm` | 退出码 1，`different`，D1 的 `pad_offset` 约为 0.60 mm |
| [变换偏心宏](../examples/gerber/macro-transformed.gbr) | 局部中心 `(1, 0)` 经 `LMX/LR90/LS2` 变为 `(0, -2)`，层坐标为 `(24, 11) mm` | 退出码 1，`different`，D1 的 `pad_offset` 约为 2.00 mm |
| [同宏通过对照](../examples/gerber/macro-transformed-pass.gbr) | 闪光点调整到 `(24, 15) mm`，几何中心回到 `(24, 13) mm` | 退出码 0，`pass` |

[实测 JSON 摘录](../examples/gerber/results.json)保留退出码、状态、D1 的证据与偏差。回归用例断言三组结果与位号归属，另测几何拒收、普通圆弧和局部清除语义。[CLI 回归](../tests/cli.test.mjs)

### 透明圆孔对照

四份文件在同一位置放置 2 × 2 mm 的外形，其中三份开直径 1 mm 的孔。D1 的核对点位于中心，刻意省略 D1 的 X2 位号，让报告只比较实际铜证据。复用上方 CLI 命令，替换最后一个文件路径即可。

| 输入 | D1 的证据 |
| --- | --- |
| [无孔对照](../examples/gerber/hole-solid.gbr) | `copper_only`，该点有铜 |
| [标准光圈圆孔](../examples/gerber/hole-standard.gbr) | `unverified`，该点落入空孔 |
| [宏内清除开孔](../examples/gerber/hole-macro.gbr) | `unverified`，该点落入空孔 |
| [宏孔下方已有铜](../examples/gerber/hole-macro-underlay.gbr) | `copper_only`，孔下先绘制的铜仍可见 |

四种情况均因 D1 无法归属而退出 2，其余四颗照常按位号核验。见[实测 JSON 摘录](../examples/gerber/results.json)。面积和几何中心从外形中扣除圆孔，单测也检查了偏心孔经镜像、旋转和缩放后的结果。透明孔及宏内清除的定义见 [Ucamco 规范 §4.4.6、§4.5.2](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf)。
