# KiCad 与嘉立创 EDA 双面实板对照

对照同一块 Antmicro USB-C PD 转接板在 KiCad 10.0.8 与嘉立创 EDA 专业版 Web 4.1.105 的坐标导出，用 KiCad 原始底铜核验 J1 的封装原点和 C17 的偏位。[原始文件、版本及许可](../examples/hardware/antmicro-usb-c-power-adapter/README.md)

## 两份原始坐标表

KiCad 导出 97 个贴装位号，顶面 53 个、底面 44 个。嘉立创导出 124 个位号，包含 KiCad 的全部 97 个。其余 27 个含测试点和其他未包含在 KiCad SMD 出口范围内的位号。MoonPlacement 现可直接读取嘉立创原始 `T`、`B` 板面。

原表直比报告 27 个额外位号、97 个封装名差异和 4 个位置差异，未发现错面、漏件或角度超限。封装名差异来自嘉立创保留了 `antmicro-footprints:` 库前缀。位置差异来自比较 KiCad 的封装原点与嘉立创的 `Mid X/Y`，其中 J1 差 **1.123 mm**，Q1 约 **0.440 mm**，J2、J3 各约 **0.183 mm**。

用[实板导入配置](../examples/hardware/antmicro-usb-c-power-adapter/import-policy.json)读取两份原始表。配置列出 KiCad SMD 导出的 97 个应贴位号，将嘉立创的 `Ref X/Y` 对应到 KiCad 封装原点，并移除这一样例的封装库前缀。两表核对通过，最大坐标差 **0.000136 mm** 在 R25。报告列出本次范围之外的 27 个位号。删除送厂表中的 C17 后，报告仍能确认漏件。[嘉立创导出字段定义](https://prodocs.lceda.cn/cn/pcb/export-pick-and-place-file/)

## 用原始底铜核对 J1 与 C17

测试通过 MoonBit 公共库传入原始底铜。44 个底面位号都有可归属的焊盘证据。J1 的封装原点离铜层质心 **2.2663 mm**。测试从固定版 KiCad PCB 中的 J1 提取 16 个圆角矩形焊盘和 4 个椭圆形安装焊盘，按每个焊盘的图形面积加权。计算保留重合的闪光焊盘，安装槽钻孔属于独立制造文件。将 KiCad PCB 中向下的 Y 换成 Gerber 中向上的 Y，得到从封装原点到质心的向量 `(-0.000715659072, -2.266301343011) mm`。[原始设计中的 J1](https://github.com/antmicro/usb-c-power-adapter/blob/4d3e9e289a294f7953bf48dde6c96af8327a0611/usb-c-power-adapter.kicad_pcb#L271195) · [计算输入](../examples/hardware/antmicro-usb-c-power-adapter/j1-design-pads.json)

| 输入 | 两表对比 | 底铜核验（容差 0.10 mm） |
| --- | --- | --- |
| 原始两表，关闭 J1 校正 | 通过 | J1 距离 2.2663 mm |
| 原始两表，使用 J1 校正 | 通过 | 44 位号通过，J1 校正后距离小于 0.000000001 mm |
| 两表的 J1 都沿 X 移动 0.30 mm | 通过 | 仅 J1 超限，校正后距离 0.30 mm |
| 两表的 C17 都沿 X 移动 0.30 mm | 通过 | 仅 C17 超限，距离 0.30 mm |

将 J1 改设为人工复查时，报告保留 2.2663 mm 的实测距离和复查原因。其余 43 个底面位号继续核验，C17 有偏移时仍报告差异。

此板的原始顶铜光圈宏 `FreePoly0` 在闭合处重复写入顶点。CLI 同时读取两层时，把顶铜标为 `failed`，仍能检查底铜的 44 个位号。原始两表加校正规则时，底铜通过，双面报告整体为 `indeterminate`。[Gerber 2024.05 §4.5.1.6、§4.10.3](https://www.ucamco.com/files/downloads/file_en/456/gerber-layer-format-specification-revision-2024-05_en.pdf)

## 复现

在 MoonPlacement 仓库根目录运行：

```sh
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/hardware/antmicro-usb-c-power-adapter/kicad-placement.csv examples/hardware/antmicro-usb-c-power-adapter/easyeda-pro-placement.csv examples/hardware/antmicro-usb-c-power-adapter/import-policy.json
python tests/cross-eda-audit.py
```

也可在[在线工作台](https://huahai29.github.io/moonplacement/)选择两份原始 CSV、`import-policy.json` 和原始顶、底铜文件。即使顶铜失败，报告仍会显示底面的 J1 校正前后距离。测试脚本验证原始文件哈希，并在 `_build/cross-eda/validation/` 写入漏件和偏位副本、JSON 报告及 `summary.json`。Windows 和 Linux CI 使用同一份输入，Linux 运行保留这些输出。
