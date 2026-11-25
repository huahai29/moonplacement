# MoonPlacement 0.2.0 版本与验收

[GitHub 版本](https://github.com/huahai29/moonplacement/releases/tag/v0.2.0) · [Mooncakes 0.2.0](https://mooncakes.io/docs/huahai29/moonplacement@0.2.0) · [更新记录](../CHANGELOG.md)

## 安装

在已有 MoonBit 项目中运行：

```sh
moon add huahai29/moonplacement@0.2.0
```

[公共 API](api.md)有三个可运行示例。用于送厂核对的 CLI 和网页构建方式见[项目说明](../README.md#安装并运行)。

## 这版可以做什么

- 在大幅 SR 拼板上直接选择单元。10×10 双面铜层验收覆盖最后一个单元。[拼板性能与复现](panel-benchmark.md#直接解析指定单元)
- 拒收明确声明为其他用途或另一板面的 Gerber。库可以用 `audit_checked` 接收结构化输入错误。[核对规则](audit.md#铜层核对)
- 保存输入文件的原始字节数和 SHA-256，供交接后复核。CLI 通过 `--receipt` 保存，网页可以直接下载。[核验凭据](receipt.md)
- 在外部 MoonBit 项目构造坐标并调用刚体、相似或仿射配准。CI 另用独立数值方法检查配准和焊盘容差。[配准数值对照](registration-validation.md) · [焊盘容差对照](pad-tolerance-validation.md)

普通报告继续使用 JSON v3。Gerber 2024.05 的实现边界和验收证据见[命令矩阵](gerber-acceptance.md#规范命令矩阵)。

## 复验安装

在该版本的源码根目录使用 `moonc v0.10.16+b1a0e846e` 和 Node.js 22.3 或更新版本，运行 `node tests/release-consumer.mjs`。脚本创建空项目，从 Mooncakes 安装该包，在 JS 和 Wasm-GC 上检查两表偏位、所选拼板单元缺少位号的证据，以及已知的刚体变换。
