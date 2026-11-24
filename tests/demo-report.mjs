import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { syncMarkdownSection } from './acceptance-doc.mjs';
import { regenerateHtml } from './generated-html.mjs';

const args = process.argv.slice(2);
assert.ok(args.length === 0 || (args.length === 1 && args[0] === '--write'),
  'Usage: node tests/demo-report.mjs [--write]');
const write = args.length === 1;
const cli = '_build/js/debug/build/cmd/main/main.js';
const tables = ['examples/baseline.csv', 'examples/delivery-ok.csv', 'examples/policy.json'];
const scratch = '_build/demo-report';
const html = join(scratch, 'panel-d1.html');
const demo = 'docs/demo';
mkdirSync(scratch, { recursive: true });

function audit(expectedExit, ...extra) {
  const run = spawnSync(process.execPath, [cli, ...tables, ...extra], { encoding: 'utf8' });
  assert.ifError(run.error);
  assert.equal(run.status, expectedExit, run.stderr || run.stdout);
  return JSON.parse(run.stdout);
}

const positions = audit(0);
const copper = regenerateHtml(html, output =>
  audit(1, 'examples/gerber/panel-cell-2x2.gbr', '--panel-cell', '2,2', '--html', output));
assert.equal(positions.status, 'pass');
assert.equal(copper.status, 'different');
assert.deepEqual(copper.differences, []);
assert.deepEqual(copper.pad_differences.map(({ ref, kind }) => [ref, kind]), [['D1', 'pad_offset']]);
const [{ row, column }] = copper.panel_cells;
assert.equal(row, 2);
assert.equal(column, 2);
const distance = copper.pad_differences[0].distance_mm.toFixed(2);
syncMarkdownSection('README.md', 'demo-summary', [
  `两张坐标表都把 D1 标在同一位置。只核对两表会得到 \`${positions.status}\`。加上 Gerber，`,
  `第 ${row} 行第 ${column} 列的铜层报告变为 \`${copper.status}\`，指出 D1 偏移 **${distance} mm**。`,
], write);
const read = path => readFileSync(path, 'utf8').replaceAll('\r\n', '\n');
const snapshot = join(demo, 'panel-d1.html');
if (write) {
  mkdirSync(demo, { recursive: true });
  writeFileSync(snapshot, read(html));
} else {
  assert.equal(read(snapshot), read(html), 'offline HTML report is stale');
}

const macro = audit(0, 'examples/gerber/macro-two-holes.gbr');
const d1 = macro.pad_evidence.find(({ ref }) => ref === 'D1').evidence;
assert.equal(d1.within_tolerance, true);
syncMarkdownSection('docs/acceptance-results.md', 'builtin-results', [
  '| 案例 | 结论 |',
  '| --- | --- |',
  `| 2×2 拼板的第 ${row} 行、第 ${column} 列 | 两表为 \`${positions.status}\`，加入铜层后为 \`${copper.status}\`。D1 偏移 ${distance} mm |`,
  `| 变换双孔宏 | \`${macro.status}\`。D1 的铜形几何中心偏离约 ${d1.distance_mm.toFixed(3)} mm，仍在 ${macro.tolerances.pad_mm} mm 容差内 |`,
], write);
console.log(`D1 demo: ${positions.status} → ${copper.status}, ${distance} mm`);
