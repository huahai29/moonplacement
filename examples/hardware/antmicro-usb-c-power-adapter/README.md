# Antmicro USB-C Power Delivery Adapter 验收文件

设计版权归 Antmicro。使用上游固定提交 `4d3e9e289a294f7953bf48dde6c96af8327a0611`，许可证为 Apache-2.0。本目录保存生成的验收输入，设计源文件可从固定提交取得。[设计源文件](https://github.com/antmicro/usb-c-power-adapter/tree/4d3e9e289a294f7953bf48dde6c96af8327a0611) · [许可证](LICENSE-Apache-2.0.txt)

| 原始输入 | 来源 |
| --- | --- |
| `kicad-placement.csv` | KiCad 10.0.8 导出双面 SMD 位置，CSV、mm，启用 `--smd-only` 和 `--exclude-dnp` |
| `usb-c-power-adapter-F_Cu.gbr`、`usb-c-power-adapter-B_Cu.gbr` | KiCad 10.0.8 同一原点的原始 Gerber X2 |
| `easyeda-pro-placement.csv` | 嘉立创 EDA 专业版 Web 4.1.105 导入同一份 KiCad 工程，再用「导出 → 坐标文件（CPL）」导出。CSV、逗号分隔、mm、数值无单位，底层坐标和角度镜像均关闭 |

[SHA-256](SHA256SUMS)固定上述四份文件的原始字节。嘉立创文件保留 UTF-8 BOM 和导出换行。[导入配置](import-policy.json)直接处理两份原始坐标表，其中的应贴清单取自固定的 KiCad SMD 导出。漏件和偏移副本由验收脚本产生。[KiCad 导出记录](https://github.com/huahai29/moonplacement/actions/runs/45578388968) · [复现实测](../../../docs/cross-eda.md)

[J1 设计焊盘](j1-design-pads.json)记录原始 `.kicad_pcb` 中用于独立计算铜箔质心的形状、尺寸和中心。导入配置以此校正 J1 的封装原点。[推导与验收](../../../docs/cross-eda.md#用原始底铜核对-j1-与-c17)
