# MoonPlacement

[![MoonPlacement 检查](https://github.com/huahai29/moonplacement/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

MoonPlacement 用来复核双面 PCB 送厂前的装配文件。输入同一版板子的设计坐标表和送厂坐标表，可以查漏件、错面、偏位和角度偏差。加入 Gerber 铜层后，还能借助焊盘位置核对两张表里可能共有的错误。

**Gerber 目标为完整读取并求值 2024.05 现行图层语义。** 当前可核验带圆孔的标准光圈、KiCad 圆角与切角焊盘、热焊盘以及带多个透明圆孔的部分光圈宏。规范覆盖与实测范围见下方验收表。

[示例与复现](examples/README.md) · [Gerber 2024.05 验收](docs/gerber-acceptance.md) · [配置与 JSON 报告](docs/audit.md)

## 跑一遍示例

**KiCad 实导出案例。** 两张坐标表都把底面 C7 偏移了 0.30 mm，两表核对返回 `pass`。加入原始顶、底铜层后，结果变为 `different`，报告指出 C7 的 `pad_offset`。[复现步骤](examples/README.md#铜层实导出验证)

安装 [MoonBit](https://www.moonbitlang.cn/download/) 和 Node.js 22.3 或更新版本。CI 使用 `moonc v0.10.16+b1a0e846e`。无需安装 npm 依赖。

```sh
git clone https://github.com/huahai29/moonplacement.git
cd moonplacement
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json
```

这条命令预期返回 `pass`。要试其他数据，替换这条三参数命令中的送厂 CSV 和配置 JSON，保留 `examples/baseline.csv`。

| 送厂表 | 配置 | 预期结果 |
| --- | --- | --- |
| `examples/delivery-errors.csv` | `examples/policy.json` | `different`。例如 C7 漏件、D1 错面、J1 偏移约 1 mm。 |
| `examples/delivery-ok.csv` | `examples/policy-ambiguous.json` | `indeterminate`。两种底面 X 约定都符合顶面基准。 |
| `examples/delivery-similarity.csv` | `examples/policy-similarity.json` | `pass`。恢复约 2.5° 的整板旋转及 1.0003 的缩放。 |

再运行下面的命令，可以核对五颗顶面器件并生成 `_build/report.html`。

```sh
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/top-copper.gbr --html _build/report.html
```

## 核对自己的板子

1. 准备两份来自同一板版次、装配范围一致的 UTF-8 坐标表。支持 KiCad 和嘉立创 CPL 风格的 CSV。坐标列填数字，单位写入配置。
2. 复制示例配置，填写两表的单位、底面 X 和角度约定，选择至少三个位置分散的可信器件作为基准。自动判断底面 X 时，通常还需要一个远离 X=0 的底面基准。[示例配置](examples/policy.json)
3. 两表方向一致时保持示例的 `"rotation": "0"`。需要尝试 0°、90°、180° 和 270° 时，设为 `"auto"`。任意角度旋转可用 `"alignment": "rigid"`，还需拟合统一缩放时用 `"similarity"`。仿射模式 `"affine"` 的适用范围见[对齐规则](docs/audit.md#怎么对齐)。
4. 运行核对命令。JSON v3 中，`differences` 记录两表差异，`frame.anchor_residuals` 可用于排查基准，`pad_evidence` 记录铜层证据。追加 `--html 报告.html` 可生成带板面示意图的报告。

## 铜层核对

Gerber 与设计坐标表应使用同一原点和坐标方向。在配置文件参数后追加顶层 Gerber，需要核对底面时再追加底层 Gerber。清除圆弧按扫过的范围和线宽筛查，能排除未受影响的焊盘；含弧铜区可区分实铜和通过折返路径围出的孔。[命令覆盖表](docs/gerber-acceptance.md#规范命令矩阵) · [圆弧清除对照](docs/gerber-acceptance.md#圆弧清除对照) · [步进重复拼板](docs/gerber-acceptance.md#步进重复拼板)

D1 算例验证了参数化光圈宏的镜像、旋转和缩放。KiCad 双面板的 U3 则验证了倾斜的圆角矩形焊盘。[输入与验证方法](docs/gerber-acceptance.md#输入命令和实测输出)

- **按位号核验**。用 X2 `TO.P` 或 `TO.C` 归集焊盘，比较送厂坐标与焊盘面积加权中心。`pad_tolerance_mm` 默认为 0.1 mm。不对称封装的贴装原点可能偏离焊盘中心，需结合封装定义复核。
- **附近有铜或未核验**。缺少焊盘归属时会标出证据状态。若其余检查没有发现差异，结果为 `indeterminate`。

## 退出码

| 退出码 | 状态 | 含义 |
| --- | --- | --- |
| 0 | `pass` | 唯一对齐，器件在容差内，所请求的铜层核验也已完成 |
| 1 | `different` | 已对齐，发现差异 |
| 2 | `indeterminate` | 无法唯一对齐、缺少独立检查对象，或所请求的铜层缺少位号证据 |
| 64 | `input_error` | 文件、参数或数据无效 |

## 验证

CSV 和 Gerber 解析、对齐、差异判定及报告均由 MoonBit 实现。CI 覆盖四个 MoonBit 后端、CLI 和 KiCad 双面实导出。[CI 记录](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

[MIT 许可证](LICENSE)
