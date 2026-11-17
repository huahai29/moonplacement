# 示例与验证

`baseline.csv` 和三份核对输入是可直接运行的人工验收数据。`two-sided.kicad_pcb` 是独立绘制的六器件双面测试板，可以用 KiCad 8 或 9 的命令行重导两份 CSV 检验实际导出兼容性。

在仓库根目录执行以下命令。

```sh
moon build --target js
kicad-cli pcb export pos --side both --format csv --units mm -o _build/kicad-baseline.csv examples/two-sided.kicad_pcb
kicad-cli pcb export pos --side both --format csv --units in --use-drill-file-origin --bottom-negate-x -o _build/kicad-delivery.csv examples/two-sided.kicad_pcb
node _build/js/debug/build/cmd/main/main.js _build/kicad-baseline.csv _build/kicad-delivery.csv examples/policy.json
```

预期是 `pass`，基准表和送厂表均为六个器件，底面约定识别为 `negated`，平移约为 `(5, -7) mm`。检查实际 CSV 后，也可以把第二条导出命令中的 `--bottom-negate-x` 去掉复跑，预期会改为 `direct`。

## 注册引擎示例

`delivery-similarity.csv` 由 `baseline.csv` 整体旋转 2.5°、缩放 1.0003、平移约 1.2 mm 后对底面 X 取反得到。用 `policy-similarity.json` 复现：

```sh
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-similarity.csv examples/policy-similarity.json
```

预期为 `pass`，`frame.rotation_deg` 约为 2.5，`frame.scale` 约为 1.0003，`frame.delivery_bottom_x` 为 `negated`。该示例走注册引擎的连续相似变换，而不是四分之一圈枚举。

## 铜层核对示例

`top-copper.gbr` 是手写的顶层铜层（RS-274X）。其中五颗顶面器件与 `baseline.csv` 一致，每个焊盘都带 X2 `TO.C` 位号属性：

```sh
node _build/js/debug/build/cmd/main/main.js examples/baseline.csv examples/delivery-ok.csv examples/policy.json examples/top-copper.gbr --html _build/report.html
```

预期为 `pass`，`pad_checked` 为 5，`pad_differences` 为空。把 `top-copper.gbr` 换成 `top-copper-shifted.gbr`（D1 的焊盘整体偏移 2 mm），预期改为 `different`，`pad_differences` 中只有 D1 的 `pad_offset`。

## 铜层实导出验证

安装 `kicad-cli` 后，在仓库根目录执行：

```sh
moon build --target js
node tests/kicad-export.mjs
```

脚本用 KiCad 实际导出两份坐标表及顶、底 Gerber，再运行 MoonPlacement。KiCad 只用于生成验收数据，使用 MoonPlacement 核对已有文件时不用安装它。输出在 `_build/kicad-evidence/`，CI 也保存这份目录。

| 用例 | 预期结果 |
| --- | --- |
| 两种底面 X 约定的正常导出 | `pass`，6 颗按位号核验，底面 C7 归集为一组双焊盘 |
| 只有送厂表的 C7 偏移 0.30 mm | `different`，两表位置和铜层均指出底面 C7 |
| 两份表的 C7 同时偏移 0.30 mm | 仅查两表为 `pass`，加入原铜层后为 `different`，唯一差异是 C7 的 `pad_offset` |

## 测试命令

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target js
moon test --target wasm-gc
moon test --target wasm
moon test --target native
moon build --target js
node --test tests/cli.test.mjs
```

MoonBit 用例覆盖 CSV 行号、带引号字段、输入校验、旋转与角度归一化、退化或异常基准和禁止的反射。命令行用例直接检查退出码与 JSON 输出。
