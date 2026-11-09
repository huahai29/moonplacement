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
