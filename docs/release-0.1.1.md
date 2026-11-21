# MoonPlacement 0.1.1 版本与验收

[GitHub 源码标签](https://github.com/huahai29/moonplacement/tree/v0.1.1) · [Mooncakes 0.1.1](https://mooncakes.io/docs/huahai29/moonplacement@0.1.1) · [更新记录](../CHANGELOG.md)

```sh
moon add huahai29/moonplacement@0.1.1
```

[最小使用示例](release-0.1.0.md#从-mooncakes-安装)中的 API 调用不变，把安装版本换成 `0.1.1` 即可。可在标签版的仓库根目录运行 `node tests/release-consumer.mjs`，验证独立项目从注册表安装后，JS 和 Wasm-GC 都能报出 D1 的 0.30 mm 偏移。工具链使用 `moonc v0.10.16+b1a0e846e`。

- [实板拼板](real-panel.md)：正常四块均通过；第 2 行第 2 列的 D1 偏移可由独立铜层检出。
- [Windows／Linux 一致性](platform-validation.md)：同一组 CLI 案例逐项比对，含中文路径和 HTML。
- [清除定位字段](audit.md#json-报告-v3)：JSON 保持 v3，增加可能受影响的引脚、Gerber 命令和清除范围。
- [性能记录](panel-benchmark.md)：大规模清除筛查改用 MoonBit 空间索引，六组输出与旧版算法对照一致。10×10 实板仍触发原展开上限。

Gerber 2024.05 是格式兼容目标，具体范围见[命令矩阵](gerber-acceptance.md#规范命令矩阵)。
