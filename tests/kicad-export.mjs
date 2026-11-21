import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const board = 'examples/two-sided.kicad_pcb';
const dir = '_build/kicad-evidence';
const copper = join(dir, 'copper');
const cli = '_build/js/debug/build/cmd/main/main.js';
const policy = 'examples/policy.json';
mkdirSync(copper, { recursive: true });

function run(file, args, exit = 0) {
  const result = spawnSync(file, args, { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, exit, `${file} ${args.join(' ')}\n${result.stdout}${result.stderr}`);
  return result.stdout;
}

const version = run('kicad-cli', ['version']).trim();
console.log(`KiCad ${version}`);
writeFileSync(join(dir, 'kicad-version.txt'), `${version}\n`);
run('kicad-cli', ['pcb', 'export', 'gerbers', '--layers', 'F.Cu,B.Cu', '--no-protel-ext', '-o', `${copper}/`, board]);

function findLayer(side) {
  const files = readdirSync(copper).filter(name => name.endsWith('.gbr')).map(name => join(copper, name));
  const matches = files.filter(file => new RegExp(`%TF\\.FileFunction,Copper,L\\d+,${side}(?:[,*])`).test(readFileSync(file, 'utf8')));
  assert.equal(matches.length, 1, `Expected one ${side} copper file in ${files.join(', ')}`);
  return matches[0];
}

const top = findLayer('Top');
const bottom = findLayer('Bot');
const topText = readFileSync(top, 'utf8');
assert.match(topText, /%AMRoundRect\*/);
assert.match(topText, /%ADD\d+RoundRect,/);
assert.match(topText, /%AM(?:Outline\d+P|FreePoly\d+)\*/);
assert.match(topText, /%ADD\d+(?:Outline\d+P|FreePoly\d+),/);
assert.match(topText, /%TO\.P,U3,1(?:,|\*)/);
assert.match(topText, /G0[23]\*/);
assert.match(topText, /[IJ][+-]?\d+[^*]*D01\*/);
assert.match(readFileSync(bottom, 'utf8'), /%TO\.P,C7,2(?:,|\*)/);

function exportPosition(file, unit, flags = []) {
  run('kicad-cli', ['pcb', 'export', 'pos', '--side', 'both', '--format', 'csv', '--units', unit, ...flags, '-o', file, board]);
}

function audit(name, baseline, delivery, exit) {
  const output = run(process.execPath, [cli, baseline, delivery, policy, top, bottom, '--html', join(dir, `${name}.html`)], exit);
  writeFileSync(join(dir, `${name}.json`), output);
  const report = JSON.parse(output);
  console.log(`${name}: ${report.status}, ${report.pad_checked} by reference, ${report.pad_differences.length} copper difference(s)`);
  return report;
}

function shiftC7(input, name, shiftInFileUnits) {
  const rows = readFileSync(input, 'utf8').trimEnd().split(/\r?\n/);
  const columns = rows[0].split(',').map(field => field.replaceAll('"', ''));
  const ref = columns.indexOf('Ref');
  const y = columns.indexOf('PosY');
  assert.ok(ref >= 0 && y >= 0);
  let changed = 0;
  const out = rows.map((row, i) => {
    if (i === 0) return row;
    // The fixture's CSV fields contain no embedded commas.
    const fields = row.split(',');
    if (fields[ref].replaceAll('"', '') !== 'C7') return row;
    const v = Number(fields[y].replaceAll('"', ''));
    assert.ok(Number.isFinite(v));
    fields[y] = (v + shiftInFileUnits).toFixed(8);
    changed += 1;
    return fields.join(',');
  });
  assert.equal(changed, 1);
  const file = join(dir, `${name}.csv`);
  writeFileSync(file, `${out.join('\n')}\n`);
  return file;
}

const baseline = join(dir, 'baseline.csv');
exportPosition(baseline, 'mm');
let negatedDelivery;
for (const mirror of ['direct', 'negated']) {
  const delivery = join(dir, `delivery-${mirror}.csv`);
  const flags = ['--use-drill-file-origin'];
  if (mirror === 'negated') flags.push('--bottom-negate-x');
  exportPosition(delivery, 'in', flags);
  const report = audit(`normal-${mirror}`, baseline, delivery, 0);
  assert.equal(report.baseline_count, 6);
  assert.equal(report.delivery_count, 6);
  assert.equal(report.frame.delivery_bottom_x, mirror);
  const shift = report.frame.delivery_to_baseline_mm;
  assert.ok(Math.abs(shift.x - 5) < 0.001 && Math.abs(shift.y + 7) < 0.001);
  assert.equal(report.pad_status, 'complete');
  assert.deepEqual(report.pad_sides, ['top', 'bottom']);
  assert.equal(report.pad_checked, 6);
  assert.ok(report.pad_warnings.every(({ message }) => !message.includes('圆弧')));
  assert.ok(report.pad_evidence.every(({ evidence }) => evidence.within_tolerance));
  assert.equal(report.pad_evidence.find(({ ref }) => ref === 'C7').evidence.pad_count, 2);
  const rounded = report.pad_evidence.find(({ ref }) => ref === 'U3').evidence;
  assert.equal(rounded.pad_count, 1);
  assert.ok(rounded.distance_mm < 0.001);
  const chamfered = report.pad_evidence.find(({ ref }) => ref === 'R2').evidence;
  assert.equal(chamfered.pad_count, 1);
  assert.ok(chamfered.distance_mm < 0.001);
  if (mirror === 'negated') negatedDelivery = delivery;
}

const movedDelivery = shiftC7(negatedDelivery, 'delivery-c7-moved', 0.30 / 25.4);
const moved = audit('wrong-delivery', baseline, movedDelivery, 1);
assert.deepEqual(moved.differences.map(({ ref, kind }) => [ref, kind]), [['C7', 'position']]);
const movedBaseline = shiftC7(baseline, 'baseline-c7-moved', 0.30);
const csvOnly = JSON.parse(run(process.execPath, [cli, movedBaseline, movedDelivery, policy]));
assert.equal(csvOnly.status, 'pass');
writeFileSync(join(dir, 'both-moved-csv-only.json'), `${JSON.stringify(csvOnly, null, 2)}\n`);
const sameError = audit('same-error-in-both-tables', movedBaseline, movedDelivery, 1);
assert.deepEqual(sameError.differences, []);
for (const report of [moved, sameError]) {
  assert.equal(report.status, 'different');
  assert.deepEqual(report.pad_differences.map(({ ref, kind }) => [ref, kind]), [['C7', 'pad_offset']]);
  assert.ok(Math.abs(report.pad_differences[0].distance_mm - 0.30) < 0.001);
}
