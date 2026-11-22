import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

const cli = '_build/js/debug/build/cmd/main/main.js';
const path = 'docs/接口契约.json';
function run(args) {
  const result = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.ok(result.stdout, result.stderr);
  return { exit: result.status, data: JSON.parse(result.stdout) };
}
const { exit, data: schema } = run(['--report-schema']);
assert.equal(exit, 0);
const tables = ['examples/baseline.csv', 'examples/delivery-ok.csv', 'examples/policy.json'];
for (const [expected, args] of [
  ['pass', tables],
  ['different', [...tables, 'examples/gerber/panel-cell-2x2.gbr', '--panel-cell', '2,2']],
  ['indeterminate', [...tables, 'examples/gerber/panel-sr.gbr']],
  ['input_error', []],
]) {
  const { exit: completed, data: report } = run(args);
  const definition = schema.$defs[expected === 'input_error' ? 'input_error' : 'audit'];
  assert.equal(report.status, expected);
  assert.equal(completed, schema['x-moonplacement-exit-codes'][expected]);
  assert.equal(report.schema_version, definition.properties.schema_version.const);
  assert.deepEqual(Object.keys(report).sort(), [...definition.required].sort());
}
const actual = JSON.stringify(schema, null, 2) + '\n';
if (process.argv[2] === '--write') writeFileSync(path, actual);
else assert.equal(readFileSync(path, 'utf8').replaceAll('\r\n', '\n'), actual,
  'Run node tests/report-contract.mjs --write to regenerate the contract after an intentional change');
console.log('Report contract matches the generated schema and all four CLI statuses');
