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
| `AM` | 部分处理 | MoonBit 单测「off-center clearance」、D1 圆孔对照、KiCad U3 实导出 | 支持单图元 1/4/5/7/20/21、KiCad 圆角轮廓组合、表达式，以及圆、中心线矩形或简单轮廓内多个互不接触的圆形清除图元。重叠圆孔、跨边界切除及其他任意组合报输入错误 |
| `Dnn` | 已实现 | 单测「parses flashes」在两种光圈间切换 | 使用未定义光圈绘图时报输入错误 |
| `D01` | 部分处理 | CLI 圆弧清除对照、KiCad 实导出 | 普通圆弧按方向和线宽求值；铜区弧段按弦离散并带误差范围。非法光圈或缺失起点报输入错误 |
| `D02` | 已实现 | 单测「trailing zero omission」 | 未建立当前位置时须提供两轴坐标 |
| `D03` | 已实现 | 三个 D1 案例、单测「macro rotation」 | 继承模态坐标。缺少位置或光圈报输入错误 |
| `G01` | 已实现 | CLI 核验直线区域与位号证据的回归文件 | 后续 D01 进入直线模式 |
| `G02` | 部分处理 | 圆弧清除对照、顺时针及整圆单测 | 支持顺时针描线及区域弧段；区域使用带误差范围的离散 |
| `G03` | 部分处理 | 逆时针、端帽及舍入误差单测 | 支持逆时针描线及区域弧段；区域使用带误差范围的离散 |
| `G75` | 部分处理 | 单测「ambiguous legacy mode」、KiCad 实导出 | 多象限模式已验证；缺少 G75 或使用旧版 G74 的圆弧报输入错误。兼容将一个为零的 I/J 省略 |
| `LP` | 部分处理 | CLI 清除在闪光前、在闪光后及位于远处的对照 | 按绘制顺序筛查受影响位号；清除区内的孔保持透明，仍不计算焊盘裁切面积 |
| `LM` | 已实现 | D1 偏心宏及单测「macro rotation」 | 识别 N/X/Y/XY。未知模式报输入错误 |
| `LR` | 已实现 | D1 偏心宏及单测「macro rotation」 | 按原始光圈应用旋转，非法角度报输入错误 |
| `LS` | 已实现 | D1 双焊盘面积加权案例及通过对照 | 按原始光圈缩放，非正或不可计算比例报输入错误 |
| `G36` | 部分处理 | 单测「regions become filled polygons」及含弧区域回归 | 支持多个闭合轮廓取并集与遵循规范的折返开孔 |
| `G37` | 部分处理 | 同一单轮廓与含弧区域回归 | 关闭铜区；未闭合轮廓、未关闭铜区报输入错误 |
| `AB` | 拒收 | CLI「rejects Gerber commands」块光圈案例 | 直接报输入错误 |
| `SR` | 拒收 | 同一 CLI 回归的步进重复案例 | 直接报输入错误 |
| `TF` | 部分处理 | D1 样例包含 `.FileFunction` | 完整文件属性保留待完成，负像文件报输入错误 |
| `TA` | 部分处理 | KiCad 双面实导出携带光圈属性 | 识别命令，当前未保留到对象。完整作用域待完成 |
| `TO` | 部分处理 | 单测「TO.P supplies the owner」 | 提取 `.P/.C`，其他对象属性的保留待完成 |
| `TD` | 部分处理 | 同一单测检查按名清除和清空 | 支持当前位号属性。完整属性字典待完成 |
| `M02` | 已实现 | 单测「trailing zero omission」检查终止 | 终止读取。兼容无终止符的旧输入 |

测试入口：[MoonBit 单测](../gerber_wbtest.mbt) · [CLI 回归](../tests/cli.test.mjs) · [KiCad 实导出](../examples/README.md#铜层实导出验证)。

发布门槛以规范 §2.12 的合规读取要求和第 3 至 5 章语义为准。按 §2.8 逐项补足后，还需将合法公开文件的几何与独立 Gerber 实现对照，校验宏、变换、极性、重复的组合及属性归属。上述矩阵用于记录进度，发布证据还应给出对照所用文件、工具版本和差异阈值。

后绘制的清除圆弧按扫过的角度、端部和线宽检查焊盘。起止半径不一致时，按半径差保留误差余量；焊盘用外接圆筛查。可能相交的位号标为 `unverified`，原因是 `possible_clearance`，其余器件照常核验。清除铜区使用各闭合轮廓筛查，边界误差带内保守处理；仍不计算裁切后的铜面积。

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

### 圆弧清除对照

用上方同一条 CLI 命令，把最后的文件换成 [`arc-clearance.gbr`](../examples/gerber/arc-clearance.gbr)。清除弧以 `(20, 10) mm` 为圆心、半径为 10 mm，从 C1 的中心 `(30, 10) mm` 顺时针扫过 90°。U3 在同一圆周却位于反方向。旧包围范围包含两颗焊盘；现在只有 C1 标记为 `possible_clearance`，U3 和其他三颗继续按位号核验，退出码为 2。见[实测 JSON 摘录](../examples/gerber/results.json)。

[KiCad 实导出](../examples/README.md#铜层实导出验证)另检查真实铜层中存在圆弧描线，且六颗器件的位号核验不受干扰。圆弧方向及起止半径误差见 [Ucamco 规范 §4.7.2](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf#page=77)。

### 含弧铜区和复杂宏对照

沿用上方命令，替换最后一个输入文件：

| 输入 | 预期和实测 |
| --- | --- |
| [清除铜区含圆孔](../examples/gerber/region-cut-in.gbr) | 清除区覆盖 C1，D1 位于半径 1 mm 的透明孔内。仅 C1 标为待复查，D1 照常核验 |
| [变换双孔宏](../examples/gerber/macro-two-holes.gbr) | 不同大小的圆孔扣除后，D1 的铜形几何中心偏移约 0.060 mm，仍在 0.1 mm 容差内 |

[实测 JSON 摘录](../examples/gerber/results.json)保留两组结果。铜区弧段以 0.001 mm 弦高为目标，达到分段上限时使用实际弦高，并计入起止半径差。边界误差带内不确认新增铜证据，清除按可能覆盖判断。多个 D02 轮廓各自填充后取并集，不把内轮廓自动解释成孔。见 [Gerber 2024.05 §4.10](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf#page=90)。

KiCad 实导出同时验证圆角 U3 和带对称切角的 R2。热焊盘的环形面积和绝缘间隙另由 MoonBit 单测验证。复杂宏仍按已支持的组合读入，暂不支持任意图元叠加、相交或跨边切除。块光圈和步进重复继续单列为拒收。
