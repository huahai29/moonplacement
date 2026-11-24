import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { padCenterToleranceMm, syncMarkdownSection } from './acceptance-doc.mjs';

const args = process.argv.slice(2);
assert.ok(args.length === 0 || (args.length === 1 && args[0] === '--write'),
  'Usage: node tests/kicad-acceptance-doc.mjs [--write]');
const write = args.length === 1;
const read = (dir, name) => JSON.parse(readFileSync(join(dir, name + '.json'), 'utf8'));
const output = 'docs/acceptance-results.md';
const table = ['| 案例 | 结论 |', '| --- | --- |'];
const copper = '_build/kicad-evidence';
const normal = ['normal-direct', 'normal-negated'].map(name => read(copper, name));
const csvOnly = read(copper, 'both-moved-csv-only');
const deliveryOnly = read(copper, 'wrong-delivery');
const both = read(copper, 'same-error-in-both-tables');
const offset = (report, ref) => {
  const difference = report.pad_differences.find(item => item.ref === ref && item.kind === 'pad_offset');
  assert.ok(difference && Number.isFinite(difference.distance_mm), `Missing copper offset for ${ref}`);
  return difference.distance_mm.toFixed(2);
};
for (const report of normal) {
  assert.equal(report.status, 'pass');
  assert.equal(report.pad_checked, normal[0].pad_checked);
  for (const ref of ['U3', 'R2']) {
    const evidence = report.pad_evidence.find(item => item.ref === ref)?.evidence;
    assert.ok(evidence?.status === 'by_reference' && evidence.distance_mm < padCenterToleranceMm);
  }
}
syncMarkdownSection(output, 'kicad-export-results', [
  ...table,
  `| 两种底面 X 约定 | \`pass\`，按位号核验 ${normal[0].pad_checked} 颗。U3 圆角宏和 R2 切角轮廓宏的中心偏差均小于 ${padCenterToleranceMm} mm |`,
  `| 只移动送厂表的 C7 | \`${deliveryOnly.status}\`，铜层检出 C7 偏移 ${offset(deliveryOnly, 'C7')} mm |`,
  `| 同时移动两张表的 C7 | 两表为 \`${csvOnly.status}\`，加入双面铜层后为 \`${both.status}\`。唯一铜层偏位为 C7，${offset(both, 'C7')} mm |`,
], write);

const panel = '_build/real-panel';
const native = read(panel, 'native-wrong-2-2');
const sr2 = read(panel, 'sr-both-tables-wrong-2-2');
const sr10 = read(panel, 'sr-both-tables-wrong-10-10');
assert.deepEqual(sr2.differences, []);
assert.deepEqual(sr10.differences, []);
syncMarkdownSection(output, 'kicad-panel-results', [
  ...table,
  `| 2×2 原生拼板，第 2 行、第 2 列 | \`${native.status}\`，报告定位到 D3001，铜层偏差 ${offset(native, 'D3001')} mm |`,
  `| 2×2 SR 拼板，第 2 行、第 2 列，两表同错 | \`${sr2.status}\`，两表无差异，铜层检出 D1 偏移 ${offset(sr2, 'D1')} mm |`,
  `| 10×10 SR 拼板，第 10 行、第 10 列，两表同错 | \`${sr10.status}\`，两表无差异，铜层检出 D1 偏移 ${offset(sr10, 'D1')} mm |`,
], write);
console.log('KiCad export and panel results match the acceptance document');
