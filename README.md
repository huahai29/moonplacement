# MoonPlacement

MoonPlacement 用来在送厂贴片前复核坐标文件。把同一版 PCB 的设计导出和准备发给贴片厂的 CSV 交给它，就能按器件位号查出漏件、多件、错面、偏位和角度偏差。

## 跑一遍示例

安装 [MoonBit](https://www.moonbitlang.cn/download/)（已用 `moonc v0.10.16+b1a0e846e` 验证）和 Node.js 22 或更新版本。无需安装 npm 依赖。

```sh
git clone https://github.com/huahai29/moonplacement.git
cd moonplacement
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json
```

这个样例中，送厂表换成了英寸、改了原点，并对底面 X 取了反号。核对结果为 `pass`。把第二个文件改成 `examples/delivery-errors.csv`，报告会指出 C7 缺失、D1 错面、J1 偏移约 1 mm、U3 相差 180°、R99 多出。保留正确的送厂表、把配置换成 `examples/policy-ambiguous.json`，可以复现底面基准不足导致的 `indeterminate`。

## 核对自己的板子

1. 导出同一板版次的基准 CSV 和送厂 CSV。支持 KiCad CSV 表头，以及嘉立创 CPL 常用的 `Designator / Mid X / Mid Y / Layer / Rotation` 表头。坐标列只填数字，单位写在配置中。
2. 复制 [示例配置](examples/policy.json)，填写两张表的单位、底面 X 约定、角度方向和零位。选至少三个可信、分散的器件位号做基准。自动核对底面 X 时，基准需要能区分两种约定，通常至少选一个远离 X=0 的底面器件。
3. 按示例命令运行，或将标准输出保存为 JSON。报告给出采用的变换、基准残差和逐器件差异。

| 退出码 | 状态 | 含义 |
| --- | --- | --- |
| 0 | `pass` | 找到唯一对齐方式，所有器件在容差内 |
| 1 | `different` | 已对齐，发现差异 |
| 2 | `indeterminate` | 基准不足、无法对齐或有多个可接受变换 |
| 64 | `input_error` | 文件、参数或数据无效 |

单位换算、坐标对齐、判定和报告都在 MoonBit 中完成。Node.js 负责给命令行提供文件读取和进程退出。两份表需要有相同的器件中心和可换算的角度约定，报告只检查文件中的信息，无法验证实物极性、焊盘 1 或贴片机设置。

[配置、对齐规则与 JSON 字段](docs/audit.md) · [示例与验证](examples/README.md) · [MIT 许可证](LICENSE)
