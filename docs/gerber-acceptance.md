# Gerber 2024.05 验收

## 完整格式支持目标

完整读取并求值 **Ucamco Gerber Layer Format Specification 2024.05 的现行图层文件**，从标准命令重建图形及其属性，再为双面 PCB 装配核验提供可追溯的焊盘证据。目标按规范第 2.8 节命令表、第 3 至 5 章语法与语义以及第 2.12 节的读取器要求验收。第 8 章废弃命令单列兼容情况。Gerber Job、钻孔文件和 Gerber 写出另行定义。[Ucamco 2024.05 规范](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf)

铜层读取、光圈几何、坐标配准、位号关联、证据判定和报告由 MoonBit 实现。Node.js 提供命令行宿主。KiCad 用于生成独立测试输入，运行核验只需已有的 CSV、配置和 Gerber 文件。

## 当前实现与后续验收

| 规范项 | 当前覆盖 | 后续验收 |
| --- | --- | --- |
| `FS/MO`、`Dnn/D02/D03` | 绝对坐标、毫米和英寸、模态坐标、标准与宏光圈闪光 | 补齐规范级语法边界和错误诊断 |
| `AD/AM` | 无孔标准光圈。宏支持单个实心圆或中心线矩形、字面量或直接引用 `AD` 参数、图元自带旋转 | 孔、多图元、清除图元、其余图元、赋值和表达式 |
| `LM/LR/LS` | 镜像再旋转及均匀缩放。每次作用于原始光圈，保持闪光坐标，更新轮廓、面积和偏心中心 | 与块光圈、重复和复杂宏组合的对照 |
| `G01/G02/G03/G75`、`D01`、`G36/G37` | 读取直线及单轮廓区域。圆弧当前会产生限制诊断 | 精确圆弧及带孔、多轮廓区域 |
| `LP`、`AB`、`SR` | 识别对象极性。清除对象使当前铜层核验不完整。块光圈和步进重复返回输入错误 | 按对象顺序合成铜层，展开块光圈和重复对象 |
| `TF/TA/TO/TD` | 焊盘归属使用 `TO.P` 或 `TO.C`，支持清除相应对象属性 | 完整保留文件、光圈和对象属性及其作用域 |

会影响铜层几何的未实现语义会拒绝核验，或保留诊断并将该层标记为未核验。JSON 的 `different` 仍可来自已确认的坐标表差异。完整支持的发布门槛是现行命令覆盖表全部通过、公开几何样例得到独立对照、关键图形组合及位号归属通过端到端测试。

## 输入、命令和实测输出

三组用例沿用同一份设计表、送厂表和配置，只更换顶层铜层。也可先复跑 [KiCad 双面实导出案例](../examples/README.md#铜层实导出验证)，查看 C7 在两张表同时偏移时如何由铜层检出。

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

[实测 JSON 摘录](../examples/gerber/results.json)保留退出码、状态、D1 的证据与偏差。回归用例会断言三组结果与位号归属，并确认尚不支持的光圈宏、步进重复、圆弧和极性合成不会给出铜层通过结论。[CLI 回归](../tests/cli.test.mjs)
