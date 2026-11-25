# Windows / Linux 一致性

GitHub Actions 在 Windows 和 Linux 使用同一份固定 MoonBit 工具链、Node.js 22 和相同输入，分别运行 JS、Wasm-GC 单测及 CLI 测试。Linux 另外运行 Wasm、Native、KiCad 实导出和 PyGerber 检查。

两个平台都校验公开库接口快照，并对 JS Release 构建运行[配准数值对照](registration-validation.md)。测试将编译告警视为失败。

跨平台比对包含正常、差异、配准歧义、相似变换、圆弧清除、正常拼板、偏移拼板和越界单元，共八例。调用同一个命令行入口，文件放在带空格和中文的临时路径下，成功生成的 HTML 必须以 UTF-8 读回，且能找到中文板面说明。

比对完整 JSON 和退出码。数组顺序、结构、文本和编号必须一致，非整数数值允许绝对差 `1e-8`。唯一归一化的是越界错误中的临时路径，该值先在各平台按实际输入路径校验，然后替换成固定文件名。

```sh
moon build --target js
node tests/platform-cases.mjs record
```

输出为 `_build/platform-cases.json`，包含平台标识和完整案例结果。下载两个平台的 CI 产物后可运行 `node tests/platform-cases.mjs compare linux.json windows.json`。该检查覆盖列出的样例和后端。
