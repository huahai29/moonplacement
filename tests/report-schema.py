import json
from pathlib import Path
import subprocess

from jsonschema import Draft202012Validator


schema = json.loads(Path("docs/接口契约.json").read_text(encoding="utf-8"))
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema)
command = ["node", "_build/js/debug/build/cmd/main/main.js"]
tables = ["examples/baseline.csv", "examples/delivery-ok.csv", "examples/policy.json"]
cross_eda = Path("examples/hardware/antmicro-usb-c-power-adapter")
cases = [
    tables,
    [*tables, "examples/gerber/panel-cell-2x2.gbr", "--panel-cell", "2,2"],
    [*tables, "examples/gerber/arc-clearance.gbr"],
    [*tables, "examples/gerber/panel-sr.gbr"],
    ["examples/baseline.csv", "examples/delivery-errors.csv", "examples/policy.json"],
    [str(cross_eda / name) for name in ("kicad-placement.csv", "easyeda-pro-placement.csv", "import-policy.json")],
    [str(cross_eda / name) for name in ("kicad-placement.csv", "easyeda-pro-placement.csv", "import-policy.json",
                                      "usb-c-power-adapter-F_Cu.gbr", "usb-c-power-adapter-B_Cu.gbr")],
    [],
]
for args in cases:
    result = subprocess.run(command + args, capture_output=True, encoding="utf-8")
    report = json.loads(result.stdout)
    error = next(validator.iter_errors(report), None)
    if error:
        details = error.context or [error]
        raise ValueError([(entry.json_path, entry.validator) for entry in details])
    assert result.returncode == schema["x-moonplacement-exit-codes"][report["status"]]
    print(f'{report["status"]}: validates against JSON Schema 2020-12')
