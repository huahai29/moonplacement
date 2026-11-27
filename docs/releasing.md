# 发布流程

GitHub 标签、GitHub Release 和 Mooncakes 模块使用同一版本号。在线工作台随通过 CI 的 `main` 部署，可能先于 Mooncakes 发布新功能。

## 准备版本

1. 更新 [`moon.mod`](../moon.mod) 的 `version` 和 [`receipt.mbt`](../receipt.mbt) 中的 `producer.package_version`。CLI 测试会检查两处版本一致。更新 README 和公共 API 文档的安装命令，将 `CHANGELOG.md` 的本次改动归入新版本。
2. 写 `docs/release-X.Y.Z.md`，记录用户可见改动、已验证的 `moonc` 版本、安装与复现命令。公开接口或报告契约有意变化时，按[参与开发](../CONTRIBUTING.md)更新快照和生成文件，并在版本说明里交代迁移方式。
3. 推送候选提交，确认对应提交的 Windows、Linux、Node.js 22/24、跨平台报告对照和归档消费者测试均通过。检查目标版本尚未发布到 Mooncakes，且 GitHub 上没有同名标签。[GitHub Actions](https://github.com/huahai29/moonplacement/actions/workflows/check.yml) · [Mooncakes 包](https://mooncakes.io/docs/huahai29/moonplacement) · [GitHub 标签](https://github.com/huahai29/moonplacement/tags)

## 打包与发布

从候选提交的干净检出执行下列命令。先核对 `git rev-parse HEAD` 与通过 CI 的提交一致，并确认 `moon version --all` 显示的 `moonc` 与 `.moonbit-version` 一致。

```sh
git status --short
git rev-parse HEAD
moon version --all
moon package --frozen --list
moon package --frozen
```

核对清单与 [`.moonignore`](../.moonignore)。Mooncakes 包提供 MoonBit 模块，工作台构建及第三方实板输入从 GitHub 对应提交取得。准备好的归档位于 `_build/publish/`，CI 会解包后从独立项目跑三个库示例和跨 EDA 实板案例。

首次发布或登录过期时先用 `moon login`。从同一干净检出执行 `moon publish --frozen`。按下节复验通过后，为该提交推送 `vX.Y.Z` 标签，并在 GitHub Releases 选择该标签，使用 `docs/release-X.Y.Z.md` 的内容发布说明。[MoonBit 发布文档](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html) · [GitHub Release 文档](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

```sh
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin refs/tags/vX.Y.Z
```

## 从注册表复验

在发布源码的根目录运行 `node tests/release-consumer.mjs`。脚本创建独立项目，从 Mooncakes 安装 `moon.mod` 声明的版本，在 JS 和 Wasm-GC 上验证 D1 偏位、拼板证据和配准。JS 实板回归使用原始底铜核对 44 个位号，再检查 C17 偏移。GitHub Release 建立后，再核对标签、Mooncakes 安装命令和该标签构建的凭据版本均指向这次发行。[0.3.0 验收方法](release-0.3.0.md)
