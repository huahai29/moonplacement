# HT42B534USB2UART 实板验收资料

原始 PCB 来自 [jiegec/HT42B534USB2UART](https://github.com/jiegec/HT42B534USB2UART/tree/d2918ef58d9195c7c295e8515ccfccd5ef9b1b4b)，固定到提交 `d2918ef58d9195c7c295e8515ccfccd5ef9b1b4b`。此处的 [KiCad PCB](HT42B534USB2UART.kicad_pcb) 与上游逐字节一致，SHA-256 为 `74de9b9319a7cc4a41e99216f717da833257030b7f74c87ac499b55782028290`。

上游硬件保留 [Solderpad Hardware License 2.1](LICENSE-Solderpad-2.1.txt)；该许可同时提供 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0) 选项。本目录的硬件设计与 MoonPlacement 的 MIT 源码分开授权。

验收组装由脚本生成：平移复制布线、元件、外形和铺铜，重填铜区，给后三块板的位号分别加 1000、2000、3000。原始板未修改，生成的拼板用于软件复现，未经制造或实物测试。见[复现步骤](../../../docs/real-panel.md)。
