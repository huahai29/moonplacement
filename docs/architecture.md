# 架构说明

MoonPlacement 先把送厂坐标换算到设计表的坐标系，再比较位号和装配参数。如果提供了 Gerber 铜层，就在同一坐标系中核对器件对应的铜形。

| 阶段 | 职责 | 入口或文件 |
| --- | --- | --- |
| 读入 | 解析两份 UTF-8 CSV 和配置，将位号、单位、板面和角度约定整理成内部数据 | [csv.mbt](../csv.mbt)、[placement.mbt](../placement.mbt)、[policy.mbt](../policy.mbt) |
| 配准 | 从基准件求唯一变换，记录每个基准的残差与候选被拒的原因 | [alignment.mbt](../alignment.mbt)、[minimax.mbt](../minimax.mbt)、[register.mbt](../register.mbt) |
| 铜层 | 解析光圈、宏、区域、极性和 X2 归属。指定 SR 单元时，仅复制所选单元，并保留其中的文件级绘制对象和顺序 | [gerber.mbt](../gerber.mbt)、[gerber_aperture.mbt](../gerber_aperture.mbt)、[gerber_panel.mbt](../gerber_panel.mbt)、[gerber_repeat.mbt](../gerber_repeat.mbt) |
| 核验 | 汇总两表差异，按位号检查焊盘质心，并应用有设计依据的原点偏移。后画清除对象可能影响焊盘时，报告受影响引脚和对应对象 | [audit.mbt](../audit.mbt)、[padcheck.mbt](../padcheck.mbt)、[pad_origin.mbt](../pad_origin.mbt)、[clearance_index.mbt](../clearance_index.mbt) |
| 交付 | 库返回结构化结论和 JSON；命令行读取文件、选择退出码并按需生成离线 HTML | [report.mbt](../report.mbt)、[cmd/main/main.mbt](../cmd/main/main.mbt) |

两表始终能比较漏件、多件和错面。位置、角度和铜层距离需要唯一配准。缺少 X2 归属时，附近有铜只是一条复查线索。已确认的差异仍会保留在报告里。

生产计算和报告由 MoonBit 实现。命令行通过 Node.js 读取和写入文件。网页在 Web Worker 中用 [MoonBit 适配层](../bridge/main.mbt)调用同一库，浏览器负责选文件、预览和下载。两处采用 [contract.mbt](../contract.mbt) 定义的报告版本和输入限制。

CI 使用 KiCad 生成实际输入，用 PyGerber 独立对照关键铜点。库入口见 [公共 API](api.md)，报告字段和边界见[核对规则](audit.md)。
