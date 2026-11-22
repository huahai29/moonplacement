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
node tests/report-contract.mjs
```

修改几何或配准时，把回归用例放在对应的 `*_wbtest.mbt`。反馈 Gerber 输出问题时，请附最小可分享的铜层、相应贴片表、导出工具和版本，以及预期状态和位号。提交第三方硬件样例时，在样例目录附上来源、许可证和改动说明。

[架构说明](docs/architecture.md)列出了各阶段的入口。[Gerber 验收表](docs/gerber-acceptance.md)记录了支持范围和可复现用例。[实板复现步骤](docs/real-panel.md)需要 KiCad 和 Python。

## 工作台和契约

```sh
moon build --target js --release
node web/build.mjs
npm --prefix web ci
npm --prefix web exec -- playwright install chromium
npm --prefix web test
```

本地预览可运行 `node web/serve.mjs`，打开终端显示的地址。Playwright 测试会启动自己的服务，测试前请先关掉手动预览。

有意修改报告定义时，先构建 debug 目标，再运行 `node tests/report-contract.mjs --write`。裸命令会核对生成文件和四种 CLI 状态。

CI 的 MoonBit 覆盖率门槛在 [tests/coverage-budget.json](tests/coverage-budget.json)。Linux 输出按文件统计。该统计来自 MoonBit 库测试，浏览器和 CLI 用例另行运行。
