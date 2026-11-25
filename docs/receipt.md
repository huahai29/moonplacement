# 核验凭据

把凭据和送厂文件一起留存。复查时可以按角色比对每份文件的 SHA-256，确认手里的文件与这次报告使用的是同一份字节内容。拼板行列、容差及核对结论都在凭据内的 `report`。

## 保存凭据

在[在线工作台](https://huahai29.github.io/moonplacement/)跑完核对后，点击「下载核验凭据」。文件与指纹均在浏览器内处理。浏览器需要 HTTPS 或 localhost 才能使用用于计算指纹的 Web Crypto。浏览器无法计算指纹时，仍可下载普通 JSON 和 HTML。

从 GitHub 主分支构建 CLI 后，可用 D1 示例生成一份凭据：

```sh
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/gerber/panel-cell-2x2.gbr --panel-cell 2,2 --receipt _build/receipt.json
```

示例返回退出码 1，凭据的 `report.panel_cells` 指向第 2 行第 2 列，`report.pad_differences` 指出 D1 的铜层偏位。退出码 0、1、2 对应的核对结论都可以保存。输入错误时不会生成凭据。

`--receipt` 与 `--html` 一样要求已存在且支持硬链接的目录，并只创建新文件。同时指定两种输出时，请使用不同路径。CLI 先保存凭据，再保存 HTML。若 HTML 写入失败，已写好的凭据会保留。

## 复查一个文件

例如，在 PowerShell 中查看基准表的哈希：

```powershell
Get-FileHash -Algorithm SHA256 examples/baseline.csv
```

Linux 下运行 `sha256sum examples/baseline.csv`。将结果与 `inputs` 中 `role` 为 `baseline` 的 `sha256` 对照，忽略十六进制字母大小写。计算使用解码前的字节，因此仅改换行或 UTF-8 BOM 也会得到不同的指纹。

| 字段 | 内容 |
| --- | --- |
| `schema` | 凭据外层格式 `moonplacement.receipt.v1` |
| `producer` | 模块清单版本、运行入口和构建的 SHA-256。CLI 使用启动的 JS 文件，工作台使用附加自身哈希导出前的 MoonBit 桥接模块字节 |
| `inputs[]` | 每份输入的角色、字节数和 SHA-256。角色为 `policy`、`baseline`、`delivery`，以及实际传入的 `top_gerber`、`bottom_gerber` |
| `report` | 本次[核对报告 v3](audit.md#json-报告-v3)，与普通 JSON 报告一致 |

凭据是未签名的 JSON。输入指纹只记录角色、长度和哈希，内嵌报告仍可能包含器件位号、坐标和设计细节。
