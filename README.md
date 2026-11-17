# MoonPlacement

[![MoonPlacement 检查](https://github.com/huahai29/moonplacement/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

MoonPlacement 用来复核双面 PCB 的装配文件。送厂前，把同一版板子的设计坐标表、送厂坐标表和可选的 Gerber 铜层交给它。两张表用来找漏件、错面、偏位和角度偏差；铜层提供独立的焊盘位置证据，即使两张表把同一颗器件写错，也能发现一部分偏差。

[KiCad 实际导出复现](examples/README.md) · [对齐规则与 JSON 报告](docs/audit.md)

## 跑一遍示例

安装 [MoonBit](https://www.moonbitlang.cn/download/) 和 Node.js 22.3 或更新版本。CI 使用 `moonc v0.10.16+b1a0e846e`。无需安装 npm 依赖。

```sh
git clone https://github.com/huahai29/moonplacement.git
cd moonplacement
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json
```

加上顶层 Gerber 做焊盘级核对，并导出 HTML 报告：

```sh
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/top-copper.gbr --html _build/report.html
```

四个样例共用 `examples/baseline.csv`。替换命令中最后两个文件即可复现另外三种结果。

| 送厂表 | 配置 | 预期结果 |
| --- | --- | --- |
| `examples/delivery-ok.csv` | `examples/policy.json` | `pass`。送厂表改用英寸、换了原点，并对底面 X 取反。对齐后器件均在容差内。 |
| `examples/delivery-errors.csv` | `examples/policy.json` | `different`。C7 漏件，D1 错面，J1 偏移约 1 mm，U3 角度相差 180°，R99 多出。 |
| `examples/delivery-ok.csv` | `examples/policy-ambiguous.json` | `indeterminate`。配置只选了顶面基准，两种底面 X 约定均满足基准检查。 |
| `examples/delivery-similarity.csv` | `examples/policy-similarity.json` | `pass`。送厂表整体旋转 2.5°、缩放 1.0003、平移约 1.2 mm，注册引擎直接解出连续变换。 |

## 注册引擎

默认 `rotation` 在 0/90/180/270 四个四分之一圈候选里枚举。若送厂表可能整体任意旋转、带轻微缩放，或个别基准点录入错误，可在配置里写 `"alignment": "rigid"`、`"similarity"` 或 `"affine"`：工具改用注册引擎直接从基准点拟合连续变换，并用一致性集合丢弃至多一个异常基准。

- `rigid` 估计旋转和平移；`similarity` 再加一个均匀尺度；`affine` 还能吸收错切与各向异性。
- 刚体和相似用闭式最小二乘，仿射用三参数法方程；三者都以 2 或 3 个点的最小样本做确定性 RANSAC，再在一致集合上重拟合。
- 报告给出旋转角、尺度、平移、逐基准残差、RMS 和一致集合。`register` 是公开函数，输入两组点即可单独调用。

## 铜层核对

追加顶面和可选的底面 Gerber 后，工具会为所提供板面的每颗送厂器件说明证据来自哪里：

- **按位号核验**：用 X2 引脚属性 `TO.P` 或位号属性 `TO.C` 归集焊盘，比较送厂坐标与焊盘面积加权中心。容差默认 0.1 mm，可用 `pad_tolerance_mm` 修改。
- **附近有铜 / 未核验**：没有识别到归属该位号的焊盘时，只给几何线索或标记证据缺失。两表没有差异也会返回 `indeterminate`，不会算作通过。
- 铜层偏差和两表差异分别记录。只提供顶层时，铜层结论只覆盖顶面。

铜层与设计坐标表应使用同一原点和坐标方向。面积加权中心适合贴装原点与焊盘中心重合的封装；不对称封装需要人工判断偏差是否合理。当前只支持 [Gerber 子集](docs/audit.md#铜层核对)。

两份表都带 `Val` / `Package` 列时，工具还会比较型号与封装，差异记为 `value` 与 `package`。

## 怎么核对

工具先统一单位，按配置尝试底面 X 约定。默认在四个四分之一圈里枚举整板旋转，对每种候选用可信器件的位置求平移，让最大基准残差尽可能小；配置 `alignment` 后改为从基准点直接拟合连续变换。只有唯一候选通过时，才逐件比较位置和角度。位号缺失时还会按几何位置配对新位号，把改名报告为 `swapped`。对齐失败或有歧义时，仍按位号列出能确认的漏件、多件和错面。

CSV 解析、单位换算、对齐和报告都由 MoonBit 实现。Node.js 为命令行提供文件读取和退出码。

## 核对自己的板子

1. 准备两份 UTF-8 CSV。支持 KiCad 导出表头和嘉立创 CPL 风格表头。坐标列使用纯数字，单位写在配置中。
2. 复制示例配置，填写两表的单位、底面 X 约定、角度方向和零位。选至少三个已确认、位置分散的器件做基准。自动判断底面 X 时，通常还需要一个远离 X=0 的底面基准。 [示例配置](examples/policy.json)
3. 运行核对命令。标准输出为 JSON v3，可查看基准残差、器件差异和铜层证据；`--html <路径>` 会同时写出带板面示意图的报告。

| 退出码 | 状态 | 含义 |
| --- | --- | --- |
| 0 | `pass` | 唯一对齐，器件在容差内，所请求的铜层核验也已完成 |
| 1 | `different` | 已对齐，发现差异 |
| 2 | `indeterminate` | 无法唯一对齐、缺少独立检查对象，或所请求的铜层缺少位号证据 |
| 64 | `input_error` | 文件、参数或数据无效 |

两张表应使用相同的器件中心定义、可换算的角度约定和一致的装配筛选范围。核对结论限于所给文件，不替代工厂装配检查。

## 验证

CI 检查构建、四个 MoonBit 后端和 CLI 退出码，并用同一块六器件双面测试板实导出两份坐标表及顶、底两份 Gerber。正常数据应通过；两张坐标表同时把底面 C7 偏移 0.30 mm 时，仅比较两表会通过，加入铜层后应定位到 C7。另有证据缺失、异常基准和容差边界的回归用例。 [复现步骤](examples/README.md#铜层实导出验证) · [CI 记录](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)

[MIT 许可证](LICENSE)
