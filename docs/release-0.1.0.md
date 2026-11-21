# MoonPlacement 0.1.0 版本与验收

**版本来源**：[GitHub v0.1.0 源码标签](https://github.com/huahai29/moonplacement/tree/v0.1.0) · [Mooncakes 0.1.0](https://mooncakes.io/docs/huahai29/moonplacement@0.1.0)

源码标签固定本页、命令行和复现样例所用的提交。Mooncakes 包提供 MoonBit 模块，包版本为 `0.1.0`，JSON 报告格式为 v3。验证使用 `moonc v0.10.16+b1a0e846e`；命令行需要 Node.js 22.3 或更新版本。

## 从 Mooncakes 安装

在项目外新建一个独立工程：

```sh
moon new placement-demo --user example
cd placement-demo
moon add huahai29/moonplacement@0.1.0
```

在工程的 `cmd/main/moon.pkg` 添加导入，并保留已有的可执行包声明：

```moonbit
import {
  "huahai29/moonplacement" @mp,
}
```

将 [最小示例](../examples/library/main.mbt.example) 的内容替换到 `cmd/main/main.mbt`，运行：

```sh
moon run cmd/main --target js
moon run cmd/main --target wasm-gc
```

两次都应输出 `different`，唯一差异为 D1 的 `position`，距离约 **0.30 mm**。示例直接调用 `read_placements`、`read_policy` 和 `audit`，无需 KiCad 或 PyGerber。也可在标签版源码根目录运行 `node tests/release-consumer.mjs` 自动验证真实注册表安装。

## 复现两条交付链路

先运行 `git clone --branch v0.1.0 https://github.com/huahai29/moonplacement.git`，进入仓库并构建 `moon build --target js`。

| 案例 | 验收结果 |
| --- | --- |
| [KiCad 双面实导出](../examples/README.md#铜层实导出验证) | 两份表都把底面 C7 偏移 0.30 mm。仅查两表为 `pass`；加入原始铜层后只报 C7 的 `pad_offset` |
| [2×2 拼板单元](../examples/README.md#核对拼板单元) | 三块正常单元通过，第 2 行第 2 列的 D1 报出约 0.30 mm 偏移；重叠或网格不一致时拒绝选定 |
| [PyGerber 独立对照](gerber-acceptance.md#块光圈与独立对照) | 两份拼板样例及 KiCad 实导出顶铜的 17 个采样点，有铜／无铜判断一致 |

[CI 记录](https://github.com/huahai29/moonplacement/actions/workflows/check.yml)包含四个 MoonBit 后端、CLI、KiCad 重新导出和独立铜层对照。更细的支持范围和输入边界见 [Gerber 命令矩阵](gerber-acceptance.md#规范命令矩阵)和[配置与报告](audit.md)。
