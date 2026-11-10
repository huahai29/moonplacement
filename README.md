# MoonPlacement

[![MoonPlacement 检查](https://github.com/huahai29/moonplacement/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

MoonPlacement 是一个用 MoonBit 写的双面 PCB 贴片坐标核对工具。送厂前，把同一版板子的设计导出表和准备交付的坐标表交给它，就能按器件位号查出漏件、多件、错面、偏位和角度偏差。

[KiCad 实际导出复现](examples/README.md) · [对齐规则与 JSON 报告](docs/audit.md)

## 跑一遍示例

安装 [MoonBit](https://www.moonbitlang.cn/download/) 和 Node.js 22.3 或更新版本。CI 使用 `moonc v0.10.16+b1a0e846e`。无需安装 npm 依赖。

```sh
git clone https://github.com/huahai29/moonplacement.git
cd moonplacement
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json
```

三个样例共用 `examples/baseline.csv`。替换命令中最后两个文件即可复现另外两种结果。

| 送厂表 | 配置 | 预期结果 |
| --- | --- | --- |
| `examples/delivery-ok.csv` | `examples/policy.json` | `pass`。送厂表改用英寸、换了原点，并对底面 X 取反。对齐后器件均在容差内。 |
| `examples/delivery-errors.csv` | `examples/policy.json` | `different`。C7 漏件，D1 错面，J1 偏移约 1 mm，U3 角度相差 180°，R99 多出。 |
| `examples/delivery-ok.csv` | `examples/policy-ambiguous.json` | `indeterminate`。配置只选了顶面基准，两种底面 X 约定均满足基准检查。 |

## 怎么核对

工具先统一单位，按配置尝试底面 X 约定和整板旋转。对每种候选，用可信器件的位置求平移，让最大基准残差尽可能小。只有唯一候选通过时，才逐件比较位置和角度。对齐失败或有歧义时，仍按位号列出能确认的漏件、多件和错面。

CSV 解析、单位换算、对齐和报告都由 MoonBit 实现。Node.js 为命令行提供文件读取和退出码。

## 核对自己的板子

1. 准备两份 UTF-8 CSV。支持 KiCad 导出表头和嘉立创 CPL 风格表头。坐标列使用纯数字，单位写在配置中。
2. 复制示例配置，填写两表的单位、底面 X 约定、角度方向和零位。选至少三个已确认、位置分散的器件做基准。自动判断底面 X 时，通常还需要一个远离 X=0 的底面基准。 [示例配置](examples/policy.json)
3. 运行核对命令。标准输出为 JSON v2，可查看每颗基准件的残差、最大残差对应的位号和逐器件差异。

| 退出码 | 状态 | 含义 |
| --- | --- | --- |
| 0 | `pass` | 找到唯一对齐方式，所有器件在容差内 |
| 1 | `different` | 已对齐，发现差异 |
| 2 | `indeterminate` | 基准不足、无法对齐或有多个可接受变换 |
| 64 | `input_error` | 文件、参数或数据无效 |

两张表应使用相同的器件中心定义、可换算的角度约定和一致的装配筛选范围。核对结论仅覆盖文件中的位号、坐标、角度和板面。

## 验证

CI 检查构建、四个 MoonBit 后端和 CLI 退出码。仓库附六器件双面 KiCad 测试板，CI 用不同单位、原点和底面 X 选项实际导出并复核。另有一条容差回归用例，确认基准容差为 0.020 mm 时，最大残差 0.0175 mm 的对齐方式能够通过。 [复现步骤](examples/README.md) · [CI 记录](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

[MIT 许可证](LICENSE)
