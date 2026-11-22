import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { cpus } from 'node:os';
import { join } from 'node:path';

const repeats = Number(process.env.MOONPLACEMENT_BENCH_SAMPLES || 5);
assert.ok(Number.isInteger(repeats) && repeats >= 3 && repeats % 2 === 1);
const real = process.argv[2] || '_build/real-panel';
const output = process.argv[3] || '_build/panel-benchmark.json';
const beforeFile = process.argv[4];
const scratch = '_build/panel-benchmark-inputs';
mkdirSync(scratch, { recursive: true });
const command = '_build/js/release/build/tests/bench/bench.js';
const realLayer = readFileSync(join(real, 'panel-sr-top.gbr'), 'utf8');
const policy = JSON.parse(readFileSync(join(real, 'sr-policy.json'), 'utf8'));
const cases = [];
const put = (name, content) => {
  const path = join(scratch, name);
  writeFileSync(path, content);
  return path;
};
for (const size of [2, 5, 10]) {
  assert.match(realLayer, /%SRX2Y2I40J32\*%/);
  const layer = realLayer.replace('%SRX2Y2I40J32*%', `%SRX${size}Y${size}I40J32*%`);
  const common = { layer: put(`routed-${size}.gbr`, layer),
    placements: join(real, 'sr-baseline.csv'), policy: join(real, 'sr-policy.json') };
  const name = `routed-${size}x${size}`;
  cases.push({ ...common, name, mode: 'panel',
    expected: size === 10 ? 'input_error' : 'pass', checked: size === 10 ? undefined : 12 },
  { ...common, name: `${name}-direct`, mode: 'panel-direct', expected: 'pass', checked: 12 });
}
for (const side of [20, 40, 70]) {
  const n = side ** 2;
  const rows = ['Ref,PosX,PosY,Rot,Side'];
  const dark = [];
  const clear = [];
  const flash = (x, y) => `X${Math.round(x * 1e6)}Y${Math.round(y * 1e6)}D03*`;
  for (let i = 0; i < n; i++) {
    const x = 2 * (i % side);
    const y = 2 * Math.floor(i / side);
    const ref = `R${i + 1}`;
    rows.push(`${ref},${x},${y},0,top`);
    dark.push(`%TO.P,${ref},1*%` + flash(x, y));
    // Most clear shapes lie between pads. Sparse confirmed candidates make
    // the exact witness numbers part of the regression comparison as well.
    const affected = i % 101 === 0;
    clear.push(flash(x + (affected ? 0 : 1), y));
    if (affected) clear.push(flash(x + 0.05, y));
  }
  const name = `clearance-${n}`;
  cases.push({ name, mode: 'whole', expected: 'indeterminate',
    checked: n - Math.ceil(n / 101),
    placements: put(`${name}.csv`, rows.join('\n') + '\n'),
    policy: put(`${name}.json`, JSON.stringify({ ...policy, anchors: ['R1', 'R2', `R${side + 1}`] })),
    layer: put(`${name}.gbr`, '%FSLAX46Y46*%\n%MOMM*%\n%ADD10C,0.30*%\nD10*\n' +
      dark.join('\n') + '\n%TD*%\n%LPC*%\n' + clear.join('\n') + '\nM02*\n'),
  });
}
const benchmark = { platform: process.platform, arch: process.arch, cpu: cpus()[0]?.model,
  node: process.version, samples: repeats, cases: {} };
function median(samples) {
  return [...samples].sort((a, b) => a - b)[Math.floor(samples.length / 2)];
}
for (const item of cases) {
  const measurements = [];
  for (let i = 0; i < repeats; i++) {
    const run = spawnSync(process.execPath, ['--expose-gc', command, item.placements,
      item.policy, item.layer, put('mode.txt', item.mode)], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
    assert.ifError(run.error);
    assert.equal(run.status, 0, `${item.name}: ${run.stderr}`);
    const row = JSON.parse(run.stdout);
    assert.equal(row.report.status, item.expected);
    assert.equal(row.report.pad_checked, item.checked);
    if (item.name === 'routed-10x10-direct') {
      assert.ok(row.peak_kib <= 128 * 1024, '10×10: peak process memory exceeded 128 MiB');
    }
    if (item.expected === 'input_error') assert.match(row.report.message, /200000.*累计上限/);
    const hash = createHash('sha256').update(JSON.stringify(row.report)).digest('hex');
    assert.ok(!measurements.length || measurements[0].hash === hash);
    measurements.push({ ...row, report: undefined, hash });
  }
  const first = measurements[0];
  benchmark.cases[item.name] = { features: first.features, selected_features: first.selected_features,
    report_sha256: first.hash };
  for (const key of ['parse_ms', 'select_ms', 'ready_ms', 'audit_ms', 'peak_kib']) {
    if (first[key] !== undefined) benchmark.cases[item.name][key] = median(measurements.map(row => row[key]));
  }
}
for (const size of [2, 5, 10]) {
  const name = `routed-${size}x${size}`;
  const direct = benchmark.cases[`${name}-direct`];
  const eager = benchmark.cases[name];
  // This fixture uses the same KiCad single-board copper at every grid size.
  assert.equal(direct.selected_features, 98, `${name}: selected copper objects`);
  assert.equal(direct.features, 98, `${name}: only one SR cell should be materialized`);
  if (size !== 10) assert.equal(direct.report_sha256, eager.report_sha256, name);
}
if (beforeFile) {
  const before = JSON.parse(readFileSync(beforeFile, 'utf8'));
  for (const [name, row] of Object.entries(before.cases)) {
    assert.equal(benchmark.cases[name]?.report_sha256, row.report_sha256, name);
  }
}
writeFileSync(output, JSON.stringify(benchmark, null, 2) + '\n');
console.table(benchmark.cases);
