# 第三方来源

MoonPlacement 的代码采用 [MIT 许可证](LICENSE)。

## 仓库中的硬件验收资料

USB 转串口板来自 jiegec 的 [HT42B534USB2UART](https://github.com/jiegec/HT42B534USB2UART/tree/d2918ef58d9195c7c295e8515ccfccd5ef9b1b4b)。仓库保留原始 PCB 文件及其 [Solderpad Hardware License 2.1](examples/hardware/ht42b534/LICENSE-Solderpad-2.1.txt)。[硬件来源说明](examples/hardware/ht42b534/README.md)记录了固定提交、原文件 SHA-256 和生成验收拼板时的改动。Mooncakes 软件包的打包规则排除了该硬件目录。

## 验证工具与实现依据

- [KiCad](https://www.kicad.org/) 用于生成贴片位置表、Gerber 铜层和实板拼板输入。[实板复现步骤](docs/real-panel.md)
- [PyGerber](https://github.com/Argmaster/pygerber) 用于独立渲染 Gerber，核对指定位置有无铜。[对照方法](docs/gerber-acceptance.md#块光圈与独立对照)
- Gerber 解析按 [Ucamco Gerber 规范](https://www.ucamco.com/en/gerber) 实现。配准算法的定义及参考链接见[核对规则](docs/audit.md#怎么对齐)。

KiCad 和 PyGerber 由验证环境单独安装。运行 MoonPlacement 无需安装这两个工具。
