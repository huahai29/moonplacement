import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const source = 'examples/hardware/ht42b534/HT42B534USB2UART.kicad_pcb';
const dir = '_build/real-panel';
const panel = join(dir, 'ht42b534-panel.kicad_pcb');
const mapping = join(dir, 'cells.json');
const copper = join(dir, 'copper');
const singleCopper = join(dir, 'single-copper');
const cli = '_build/js/debug/build/cmd/main/main.js';
const scope = ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'D1', 'R1', 'R2', 'R3', 'U1'];
const anchors = ['C1', 'C3', 'R3'];
const convention = { unit: 'mm', bottom_x: 'direct', angle_sign: 1,
  top_angle_offset_deg: 0, bottom_angle_offset_deg: 0 };
mkdirSync(copper, { recursive: true });
mkdirSync(singleCopper, { recursive: true });

function run(file, args, exit = 0) {
  const result = spawnSync(file, args, { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  assert.ifError(result.error);
  assert.equal(result.status, exit, `${file} ${args.join(' ')}\n${result.stdout}${result.stderr}`);
  return result.stdout;
}

function exportGerber(board, destination) {
  run('kicad-cli', ['pcb', 'export', 'gerbers', '--layers', 'F.Cu,B.Cu', '--no-protel-ext', '-o', `${destination}/`, board]);
  return ['Top', 'Bot'].map(side => {
    const matches = readdirSync(destination).filter(name => name.endsWith('.gbr'))
      .map(name => join(destination, name))
      .filter(file => new RegExp(`%TF\\.FileFunction,Copper,L\\d+,${side}(?:[,*])`).test(readFileSync(file, 'utf8')));
    assert.equal(matches.length, 1, `${board}: expected one ${side} copper file`);
    return matches[0];
  });
}

function exportPosition(board, file) {
  run('kicad-cli', ['pcb', 'export', 'pos', '--side', 'both', '--format', 'csv', '--units', 'mm',
    '--smd-only', '-o', file, board]);
  const rows = readFileSync(file, 'utf8').trimEnd().split(/\r?\n/).slice(1);
  const result = new Map();
  for (const row of rows) {
    // Only numeric fields, side and reference enter the audit; the two text
    // columns are consumed as quoted CSV even if their values contain commas.
    const parse = /^"([^"]+)","(?:[^"]|"")*","(?:[^"]|"")*",([^,]+),([^,]+),([^,]+),"?([a-z]+)"?$/i.exec(row);
    assert.ok(parse, `Unexpected KiCad position row: ${row}`);
    const [, ref, x, y, rotation, side] = parse;
    assert.ok([x, y, rotation].every(value => Number.isFinite(Number(value))), row);
    assert.ok(!result.has(ref), `Repeated native KiCad reference ${ref}`);
    result.set(ref, { x: Number(x), y: Number(y), rotation: Number(rotation), side });
  }
  return result;
}

function writePlacements(name, records) {
  const file = join(dir, name + '.csv');
  writeFileSync(file, 'Ref,PosX,PosY,Rot,Side\n' +
    records.map(({ ref, x, y, rotation, side }) => `${ref},${x.toFixed(6)},${y.toFixed(6)},${rotation},${side}`).join('\n') + '\n');
  return file;
}

function writePolicy(name, refs) {
  const file = join(dir, name + '-policy.json');
  writeFileSync(file, JSON.stringify({ baseline: convention, delivery: convention,
    anchors: refs, rotation: '0', position_tolerance_mm: 0.05, angle_tolerance_deg: 1,
    anchor_tolerance_mm: 0.02, pad_tolerance_mm: 0.10 }, null, 2));
  return file;
}

function audit(name, baseline, delivery, policy, layers, selector, exit) {
  const html = join(dir, name + '.html');
  const output = run(process.execPath, [cli, baseline, delivery, policy, ...layers,
    ...selector, '--html', html], exit);
  writeFileSync(join(dir, name + '.json'), output);
  return JSON.parse(output);
}

const version = run('kicad-cli', ['version']).trim();
const sourceDigest = createHash('sha256').update(readFileSync(source)).digest('hex');
assert.equal(sourceDigest, '74de9b9319a7cc4a41e99216f717da833257030b7f74c87ac499b55782028290');
run(process.env.MOONPLACEMENT_PCBNEW_PYTHON || '/usr/bin/python3',
  ['tests/kicad-panelize.py', source, panel, mapping]);
const cells = JSON.parse(readFileSync(mapping, 'utf8'));
const nativeLayers = exportGerber(panel, copper);
const singleLayers = exportGerber(source, singleCopper);
const original = exportPosition(source, join(dir, 'single-positions-native.csv'));
const exported = exportPosition(panel, join(dir, 'panel-positions-native.csv'));
const srLayers = singleLayers.map((file, index) => {
  const text = readFileSync(file, 'utf8');
  const marker = 'G04 APERTURE END LIST*';
  const start = text.indexOf(marker) + marker.length;
  assert.ok(text.includes(marker) && /M02\*\s*$/.test(text));
  const name = join(dir, index ? 'panel-sr-bottom.gbr' : 'panel-sr-top.gbr');
  writeFileSync(name, text.slice(0, start) + '\n%SRX2Y2I40J32*%' +
    text.slice(start).replace(/M02\*\s*$/, '%SR*%\nM02*\n'));
  return name;
});
const localRecords = scope.map(ref => {
  const placement = original.get(ref);
  assert.ok(placement && placement.side === 'top', ref);
  return { ...placement, ref };
});
const baseline = writePlacements('sr-baseline', localRecords);
const srPolicy = writePolicy('sr', anchors);
const outcomes = [];
for (const { row, column, refs } of cells) {
  const id = `${row}-${column}`;
  const records = localRecords.map(first => {
    const value = exported.get(refs[first.ref]);
    assert.ok(value && value.side === first.side, refs[first.ref]);
    assert.ok(Math.abs(value.x - first.x - (column - 1) * 40) < 1e-6, refs[first.ref]);
    assert.ok(Math.abs(value.y - first.y - (row - 1) * 32) < 1e-6, refs[first.ref]);
    return { ...value, ref: refs[first.ref] };
  });
  const scoped = writePlacements('native-' + id, records);
  const nativePolicy = writePolicy('native-' + id, anchors.map(ref => refs[ref]));
  const clean = audit('native-control-' + id, scoped, scoped, nativePolicy, nativeLayers, [], 0);
  const sr = audit('sr-control-' + id, baseline, baseline, srPolicy, srLayers,
    ['--panel-cell', `${row},${column}`], 0);
  assert.equal(clean.pad_checked, scope.length);
  assert.equal(sr.pad_checked, scope.length);
  assert.ok(sr.panel_cells.every(cell => cell.row === row && cell.column === column));
  outcomes.push({ row, column, native: clean.status, sr: sr.status, checked: sr.pad_checked });
  if (row !== 2 || column !== 2) continue;
  const corrupted = records.map(item => item.ref === refs.D1 ? { ...item, x: item.x + 0.30 } : item);
  const wrong = writePlacements('native-wrong-' + id, corrupted);
  const bad = audit('native-wrong-' + id, scoped, wrong, nativePolicy, nativeLayers, [], 1);
  const badLocal = writePlacements('sr-wrong-' + id, localRecords.map(item =>
    item.ref === 'D1' ? { ...item, x: item.x + 0.30 } : item));
  const badSr = audit('sr-wrong-' + id, baseline, badLocal, srPolicy, srLayers,
    ['--panel-cell', `${row},${column}`], 1);
  const common = audit('sr-both-tables-wrong-' + id, badLocal, badLocal, srPolicy, srLayers,
    ['--panel-cell', `${row},${column}`], 1);
  for (const [report, ref] of [[bad, refs.D1], [badSr, 'D1'], [common, 'D1']]) {
    assert.equal(report.status, 'different');
    assert.deepEqual(report.pad_differences.map(item => [item.ref, item.kind]), [[ref, 'pad_offset']]);
    assert.ok(Math.abs(report.pad_differences[0].distance_mm - 0.30) < 0.001);
  }
  assert.deepEqual(common.differences, []);
  outcomes.at(-1).injected = { panel_ref: refs.D1, local_ref: 'D1', x_mm: 0.30,
    pad_distance_mm: common.pad_differences[0].distance_mm };
}
writeFileSync(join(dir, 'acceptance.json'), JSON.stringify({
  kicad: version, source_sha256: sourceDigest, scoped_refs: scope, outcomes,
}, null, 2) + '\n');
console.log(`KiCad ${version}: 4 native and 4 SR controls passed; row 2 column 2 D1 moved 0.30 mm`);
