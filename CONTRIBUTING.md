# 参与开发

安装 README 里的 MoonBit 和 Node.js，从仓库根目录运行下面的命令。

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target js
moon test --target wasm-gc
moon build --target js
node --test tests/cli.test.mjs
node tests/demo-report.mjs
```

修改几何或配准时，把回归用例放在对应的 `*_wbtest.mbt`。反馈 Gerber 输出问题时，请附最小可分享的铜层、相应贴片表、导出工具和版本，以及预期状态和位号。提交第三方硬件样例时，在样例目录附上来源、许可证和改动说明。

[架构说明](docs/architecture.md)列出了各阶段的入口。[Gerber 验收表](docs/gerber-acceptance.md)记录了支持范围和可复现用例。[实板复现步骤](docs/real-panel.md)需要 KiCad 和 Python。
