# KiCad 与嘉立创 EDA 双面实板对照

对照同一块 Antmicro USB-C PD 转接板在 KiCad 10.0.8 与嘉立创 EDA 专业版 Web 4.1.105 的坐标导出，用 KiCad 原始底铜验证底面 C17 的偏位。[原始文件、版本及许可](../examples/hardware/antmicro-usb-c-power-adapter/README.md)

## 两份原始坐标表

KiCad 导出 97 个贴装位号，顶面 53 个、底面 44 个。嘉立创导出 124 个位号，包含 KiCad 的全部 97 个。其余 27 个含测试点和其他未包含在 KiCad SMD 出口范围内的位号。MoonPlacement 现可直接读取嘉立创原始 `T`、`B` 板面。

原表直比报告 27 个额外位号、97 个封装名差异和 4 个位置差异，未发现错面、漏件或角度超限。封装名差异来自嘉立创保留了 `antmicro-footprints:` 库前缀。位置差异来自比较 KiCad 的封装原点与嘉立创的 `Mid X/Y`，其中 J1 差 **1.123 mm**，Q1 约 **0.440 mm**，J2、J3 各约 **0.183 mm**。

按同一装配范围取 97 个位号，将嘉立创 `Ref X/Y` 对应到 KiCad 封装原点，并去掉这一样例中明确的封装库前缀后，两表核对通过。最大坐标差 **0.000136 mm** 在 R25。表格原始输入和两种报告均可复查。[嘉立创导出字段定义](https://prodocs.lceda.cn/cn/pcb/export-pick-and-place-file/)

## 用原始底铜核对 C17

测试通过 MoonBit 公共库传入原始底铜。44 个底面位号都有可归属的焊盘证据。未注入偏移时，C17 在容差内，J1 的封装原点与底铜质心相差 **2.2663 mm**，因此底铜报告整体为 `different`。

| 输入 | 两表对比 | 原始底铜对 C17 的判断 |
| --- | --- | --- |
| 两表使用同一原点口径 | 通过 | 在容差内 |
| 只移动嘉立创表中 C17 的 X 坐标 | C17 偏移 0.30 mm | C17 偏移 0.30 mm |
| 两表都移动 C17 的 X 坐标 | 通过 | C17 偏移 0.30 mm |

此板的原始顶铜光圈宏 `FreePoly0` 在闭合处重复写入顶点，CLI 返回 `input_error`。回归保留原始文件和拒收行为。表中数字来自原始底铜路径，说明的是底面证据。[Gerber 2024.05 §4.5.1.6、§4.10.3](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf)

## 复现

在 MoonPlacement 仓库根目录运行：

```sh
moon build --target js
python tests/cross-eda-audit.py
```

脚本验证原始文件哈希，在 `_build/cross-eda/validation/` 写入派生 CSV、六份 JSON 报告及 `summary.json`。Windows 和 Linux CI 使用同一份输入，Linux 运行保留这些输出。
