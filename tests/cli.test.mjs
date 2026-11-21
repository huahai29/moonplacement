import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const bin = '_build/js/debug/build/cmd/main/main.js';
const baseline = 'examples/baseline.csv';
const delivery = 'examples/delivery-ok.csv';
const policy = 'examples/policy.json';
const gerberExamples = 'examples/gerber';

function run(args, expectedExit) {
  const result = spawnSync(process.execPath, [bin, ...args], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, expectedExit, result.stderr || result.stdout);
  return JSON.parse(result.stdout);
}

test('evaluates flash scaling and transformed aperture macros before auditing pads', () => {
  for (const [file, exit, status, count, distance] of [
    ['pad-scaled.gbr', 1, 'different', 2, 0.6],
    ['macro-transformed.gbr', 1, 'different', 1, 2.0],
    ['macro-transformed-pass.gbr', 0, 'pass', 1, 0.0],
  ]) {
    const report = run([baseline, delivery, policy, join(gerberExamples, file)], exit);
    assert.equal(report.status, status, file);
    assert.equal(report.pad_status, 'complete', file);
    assert.deepEqual(report.differences, [], file);
    assert.deepEqual(report.pad_warnings, [], file);
    const pad = report.pad_evidence.find(item => item.ref === 'D1');
    assert.equal(pad.evidence.pad_count, count, file);
    assert.equal(pad.evidence.within_tolerance, exit === 0, file);
    assert.ok(Math.abs(pad.evidence.distance_mm - distance) < 0.0001, file);
    assert.deepEqual(report.pad_differences.map(({ ref, kind }) => [ref, kind]),
      exit === 1 ? [['D1', 'pad_offset']] : [], file);
  }
});

test('distinguishes transparent holes from solid copper and preserves earlier copper', () => {
  for (const [file, evidence] of [
    ['hole-solid.gbr', 'copper_only'],
    ['hole-standard.gbr', 'unverified'],
    ['hole-macro.gbr', 'unverified'],
    ['hole-macro-underlay.gbr', 'copper_only'],
  ]) {
    const report = run([baseline, delivery, policy, join(gerberExamples, file)], 2);
    assert.equal(report.reason, 'insufficient_pad_evidence', file);
    assert.equal(report.pad_checked, 4, file);
    assert.equal(report.pad_status, 'incomplete', file);
    assert.deepEqual(report.pad_evidence.find(({ ref }) => ref === 'D1').evidence,
      { status: evidence }, file);
    assert.deepEqual(report.pad_differences, [], file);
    assert.deepEqual(report.pad_warnings, [], file);
  }
});

test('rejects Gerber commands whose geometry cannot be isolated', t => {
  const work = mkdtempSync(join(tmpdir(), 'moonplacement-gerber-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const file = join(work, 'case.gbr');
  const original = readFileSync(join(gerberExamples, 'macro-transformed-pass.gbr'), 'utf8');
  for (const [input, message] of [
    [original.replace('1,1,$1,$2,0,0*%', '1,1,$1,$2,0,0*1,0,0.2,0,0,0*%'), /圆孔必须/],
    [original.replace('1,1,$1,$2,0,0*%', '1,1,$1,$2,0,0*1,0,0.2,0,0,0*1,1,0.1,0,0,0*%'), /多图元光圈宏/],
    [original.replace('M02*', '%SRX2Y1I1J0*%M02*'), /步进重复缺少结束/],
    [original.replace('M02*', '%ABD20*%M02*'), /块光圈缺少结束/],
  ]) {
    writeFileSync(file, input);
    assert.match(run([baseline, delivery, policy, file], 64).message, message);
  }
});

test('AB inside SR agrees with manually expanded flashes and flags only duplicate ownership', () => {
  const compact = run([baseline, delivery, policy, join(gerberExamples, 'panel-ab-sr.gbr')], 2);
  const explicit = run([baseline, delivery, policy, join(gerberExamples, 'panel-ab-expanded.gbr')], 2);
  assert.deepEqual(compact.pad_differences, explicit.pad_differences);
  assert.equal(compact.pad_checked, 4);
  assert.deepEqual(compact.pad_evidence.filter(e => e.ref !== 'D1'),
    explicit.pad_evidence.filter(e => e.ref !== 'D1'));
  assert.deepEqual(compact.pad_evidence.find(e => e.ref === 'D1').evidence,
    { status: 'unverified', reason: 'repeated_reference' });
  assert.deepEqual(explicit.pad_evidence.find(e => e.ref === 'D1').evidence,
    { status: 'copper_only' });
});

test('panel repeats do not average duplicated references into a phantom pad offset', t => {
  const work = mkdtempSync(join(tmpdir(), 'moonplacement-panel-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const html = join(work, 'panel.html');
  const report = run([baseline, delivery, policy, join(gerberExamples, 'panel-sr.gbr'), '--html', html], 2);
  assert.equal(report.status, 'indeterminate');
  assert.equal(report.pad_checked, 4);
  assert.deepEqual(report.pad_differences, []);
  assert.deepEqual(report.pad_evidence.find(({ ref }) => ref === 'D1').evidence,
    { status: 'unverified', reason: 'repeated_reference' });
  assert.match(readFileSync(html, 'utf8'), /D1（顶面）：拼板中位号重复，请按单元拆分后核验/);
});

test('selects each cell of a 2x2 panel and identifies only the shifted D1', t => {
  const work = mkdtempSync(join(tmpdir(), 'moonplacement-cell-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const panel = join(gerberExamples, 'panel-cell-2x2.gbr');
  const html = join(work, 'cell.html');
  for (const row of [1, 2]) {
    for (const column of [1, 2]) {
      const shifted = row === 2 && column === 2;
      const report = run([baseline, delivery, policy, panel, '--panel-cell', `${row},${column}`, '--html', html],
        shifted ? 1 : 0);
      assert.equal(report.pad_checked, 5);
      assert.equal(report.pad_status, 'complete');
      assert.deepEqual(report.differences, []);
      assert.deepEqual(report.panel_cells, [{ side: 'top', row, column, rows: 2, columns: 2,
        offset_x_mm: (column - 1) * 40, offset_y_mm: (row - 1) * 40 }]);
      const expected = shifted ? [['D1', 'pad_offset']] : [];
      assert.deepEqual(report.pad_differences.map(({ ref, kind }) => [ref, kind]), expected);
      if (shifted) assert.ok(Math.abs(report.pad_differences[0].distance_mm - 0.30) < 0.0001);
      assert.match(readFileSync(html, 'utf8'), new RegExp(`顶面拼板单元：第 ${row} 行，第 ${column} 列`));
    }
  }
});

test('panel cell selection rejects invalid indexes, missing grids and crossing geometry', t => {
  const work = mkdtempSync(join(tmpdir(), 'moonplacement-bad-panel-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const panel = join(gerberExamples, 'panel-cell-2x2.gbr');
  const original = readFileSync(panel, 'utf8');
  const scratch = join(work, 'bad.gbr');
  for (const [args, message] of [
    [[panel, '--panel-cell', '3,1'], /超出范围/],
    [[panel, '--panel-cell', '0,1'], /从 1 开始/],
    [[panel, '--panel-cell', '1,2,3'], /行,列/],
    [[panel, '--panel-cell', '1,2', '--panel-cell', '1,1'], /只能提供一次/],
    [[panel, '--panel-cell'], /只能提供一次/],
    [['--panel-cell', '1,2'], /需要提供 Gerber/],
    [['examples/top-copper.gbr', '--panel-cell', '1,1'], /恰好有一组/],
  ]) {
    assert.match(run([baseline, delivery, policy, ...args], 64).message, message);
  }
  for (const [edited, message] of [
    [original.replace('I40J40', 'I20J40'), /重叠、相切/],
    [original.replace('M02*', 'D10*X40000000Y13000000D03*M02*'), /跨越拼板单元边界/],
  ]) {
    writeFileSync(scratch, edited);
    assert.match(run([baseline, delivery, policy, scratch, '--panel-cell', '1,1'], 64).message, message);
  }
  writeFileSync(scratch, original.replace('I40J40', 'I41J40'));
  assert.match(run([baseline, delivery, policy, panel, scratch, '--panel-cell', '1,1'], 64).message,
    /顶层与底层 SR 网格/);
});

test('keeps unrelated flash evidence when a layer has arcs or clear objects', t => {
  const work = mkdtempSync(join(tmpdir(), 'moonplacement-clearance-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const file = join(work, 'case.gbr');
  const original = readFileSync(join(gerberExamples, 'macro-transformed-pass.gbr'), 'utf8');
  const reset = '%LMN*%%LR0*%%LS1*%D10*';
  const arc = direction => reset + 'X24000000Y13400000D02*G75*' + direction +
    '*X24400000Y13000000I0J-400000D01*';
  for (const [statement, message] of [
    [arc('G02'), null],
    [arc('G03'), null],
    [reset + '%LPC*%X40000000Y40000000D03*', /清除对象/],
  ]) {
    writeFileSync(file, original.replace('M02*', statement + 'M02*'));
    const report = run([baseline, delivery, policy, file], 0);
    assert.equal(report.pad_status, 'complete');
    assert.equal(report.pad_checked, 5);
    if (message) assert.match(report.pad_warnings[0].message, message);
    else assert.deepEqual(report.pad_warnings, []);
  }
  for (const [statement, kind] of [
    [reset + '%LPC*%X24000000Y13000000D03*', 'flash'],
    [reset + '%LPC*%G01*X23500000Y13000000D02*X24500000D01*', 'line'],
    ['%LPC*%' + arc('G03'), 'arc'],
    ['%LPC*%G75*G36*X24000000Y13400000D02*G03*' +
      'X24400000Y13000000I0J-400000D01*G01*X24000000Y13400000D01*G37*', 'region'],
  ]) {
    writeFileSync(file, original.replace('M02*', statement + 'M02*'));
    const report = run([baseline, delivery, policy, file], 2);
    assert.equal(report.reason, 'insufficient_pad_evidence');
    assert.equal(report.pad_status, 'incomplete');
    assert.equal(report.pad_checked, 4);
    const { clearance, ...status } = report.pad_evidence.find(item => item.ref === 'D1').evidence;
    assert.deepEqual(status, { status: 'unverified', reason: 'possible_clearance' });
    assert.equal(clearance.pad.pin, '1');
    assert.ok(Math.abs(clearance.pad.x_mm - 24) < 1e-8);
    assert.ok(Math.abs(clearance.pad.y_mm - 13) < 1e-8);
    assert.equal(clearance.object.kind, kind);
    assert.ok(clearance.object.object_number > clearance.pad.object_number);
    assert.ok(clearance.object.statement_number > clearance.pad.statement_number);
    assert.ok(Object.values(clearance.object.bounds_mm).every(Number.isFinite));
    assert.deepEqual(report.pad_differences, []);
  }
  writeFileSync(file, original.replace('%TO.P,D1,1*%',
    '%LPC*%X24000000Y13000000D03*%LPD*%%TO.P,D1,1*%'));
  const repainted = run([baseline, delivery, policy, file], 0);
  assert.equal(repainted.pad_checked, 5);
  assert.match(repainted.pad_warnings[0].message, /清除对象/);
});

test('clearance follows the arc sweep and records the affected pin and object in HTML', t => {
  const work = mkdtempSync(join(tmpdir(), 'moonplacement-clear-html-'));
  t.after(() => rmSync(work, { recursive: true, force: true }));
  const html = join(work, 'report.html');
  const file = join(gerberExamples, 'arc-clearance.gbr');
  const report = run([baseline, delivery, policy, file, '--html', html], 2);
  assert.equal(report.pad_status, 'incomplete');
  assert.equal(report.pad_checked, 4);
  const unverified = report.pad_evidence.filter(({ evidence }) => evidence.status === 'unverified');
  assert.deepEqual(unverified.map(({ ref, side, evidence }) => [ref, side, evidence.reason]),
    [['C1', 'top', 'possible_clearance']]);
  assert.equal(unverified[0].evidence.clearance.object.kind, 'arc');
  assert.match(readFileSync(html, 'utf8'), /C1（顶面）.*引脚 1 中心 \(30, 10\) mm.*清除圆弧 #\d+/);
  const u3 = report.pad_evidence.find(({ ref }) => ref === 'U3').evidence;
  assert.equal(u3.status, 'by_reference');
  assert.equal(u3.within_tolerance, true);
  assert.deepEqual(report.pad_differences, []);
});

test('clears the copper in an arc region while preserving a pad inside its cut-in', () => {
  const report = run([baseline, delivery, policy, join(gerberExamples, 'region-cut-in.gbr')], 2);
  assert.equal(report.pad_checked, 4);
  assert.deepEqual(report.pad_evidence.filter(({ evidence }) => evidence.status === 'unverified')
    .map(({ ref, side, evidence }) => [ref, side, evidence.reason, evidence.clearance.object.kind]),
    [['C1', 'top', 'possible_clearance', 'region']]);
  assert.equal(report.pad_evidence.find(({ ref }) => ref === 'D1').evidence.within_tolerance, true);
});

test('two-hole aperture reports the transformed centroid of the remaining copper', () => {
  const report = run([baseline, delivery, policy, join(gerberExamples, 'macro-two-holes.gbr')], 0);
  const evidence = report.pad_evidence.find(({ ref }) => ref === 'D1').evidence;
  const expected = 2 * Math.PI * (0.6 ** 2 * 0.8 - 0.4 ** 2) /
    (15 - Math.PI * (0.4 ** 2 + 0.6 ** 2));
  assert.equal(evidence.pad_count, 1);
  assert.ok(Math.abs(evidence.distance_mm - expected) < 0.0001);
  assert.deepEqual(report.pad_differences, []);
});

test('normalizes inches, origin shift and bottom X', () => {
  const report = run([baseline, delivery, policy], 0);
  assert.equal(report.schema_version, 3);
  assert.equal(report.status, 'pass');
  assert.equal(report.frame.delivery_bottom_x, 'negated');
  assert.ok(Math.abs(report.frame.delivery_to_baseline_mm.x - 5) < 0.00002);
  assert.ok(Math.abs(report.frame.delivery_to_baseline_mm.y - 7) < 0.00002);
  assert.deepEqual(report.anchor_issues, []);
  assert.deepEqual(report.frame.anchor_residuals.map(({ ref }) => ref), report.anchors);
  assert.ok(report.frame.anchor_residuals.every(anchor => anchor.within_anchor_tolerance));
  assert.deepEqual(report.differences, []);
});

test('reports missing, wrong side, position, angle and extra designators', () => {
  const report = run([baseline, 'examples/delivery-errors.csv', policy], 1);
  assert.equal(report.status, 'different');
  assert.deepEqual(
    report.differences.map(({ ref, kind }) => [ref, kind]),
    [['C7', 'missing'], ['D1', 'side'], ['J1', 'position'], ['U3', 'angle'], ['R99', 'extra']],
  );
  assert.ok(Math.abs(report.differences[2].distance_mm - 1) < 0.00003);
  assert.equal(report.differences[3].delta_deg, -180);
});

test('reports an ambiguous frame with evidence for both conventions', () => {
  const report = run([baseline, delivery, 'examples/policy-ambiguous.json'], 2);
  assert.equal(report.status, 'indeterminate');
  assert.equal(report.reason, 'ambiguous_frame');
  assert.equal(report.frame, null);
  assert.deepEqual(report.candidate_frames.map(frame => frame.delivery_bottom_x), ['direct', 'negated']);
  assert.ok(report.candidate_frames.every(frame => frame.anchor_residuals.length === 3));
});

test('registers a continuous rotation and scale from the anchors', () => {
  const report = run(
    [baseline, 'examples/delivery-similarity.csv', 'examples/policy-similarity.json'],
    0,
  );
  assert.equal(report.schema_version, 3);
  assert.equal(report.status, 'pass');
  assert.equal(report.frame.delivery_bottom_x, 'negated');
  assert.ok(Math.abs(report.frame.rotation_deg - 2.5) < 1e-4);
  assert.ok(Math.abs(report.frame.scale - 1.0003) < 1e-6);
  assert.ok(Math.abs(report.frame.delivery_to_baseline_mm.x - 1.2) < 1e-5);
  assert.ok(report.frame.anchor_residuals.every(anchor => anchor.inlier));
  assert.deepEqual(report.differences, []);
});

test('cross-checks delivery coordinates against a Gerber copper layer', () => {
  const report = run([baseline, delivery, policy, 'examples/top-copper.gbr'], 0);
  assert.equal(report.status, 'pass');
  assert.equal(report.pad_checked, 5);
  assert.equal(report.pad_status, 'complete');
  assert.deepEqual(report.pad_sides, ['top']);
  assert.ok(report.pad_evidence.every(({evidence}) => evidence.within_tolerance));
  assert.deepEqual(report.pad_differences, []);
});

test('incomplete pad ownership never becomes a pass or hides a known offset', t => {
  const directory = mkdtempSync(join(tmpdir(), 'moonplacement-copper-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const copper = join(directory, 'partial.gbr');
  const good = readFileSync('examples/top-copper.gbr', 'utf8');
  const shifted = good.replace('X24000000Y13000000D03', 'X26000000Y13000000D03');
  const find = (report, ref) => report.pad_evidence.find(item => item.ref === ref).evidence;
  for (const [text, status] of [[good, 'copper_only'], [shifted, 'unverified']]) {
    writeFileSync(copper, text.replace('%TO.C,D1*%', '%TD*%'));
    const report = run([baseline, delivery, policy, copper], 2);
    assert.equal(report.reason, 'insufficient_pad_evidence');
    assert.equal(report.pad_status, 'incomplete');
    assert.equal(report.pad_checked, 4);
    assert.equal(find(report, 'D1').status, status);
    assert.deepEqual(report.pad_differences, []);
  }
  const pins = shifted.replace(/%TO\.C,([^*]+)\*%/g, '%TO.P,$1,1*%');
  writeFileSync(copper, pins.replace('X26000000Y13000000D03', 'X24300000Y13000000D03')
    .replace('%TO.P,U3,1*%', '%TD*%'));
  const report = run([baseline, delivery, policy, copper], 1);
  assert.equal(report.pad_status, 'incomplete');
  assert.equal(find(report, 'U3').status, 'copper_only');
  assert.equal(find(report, 'D1').within_tolerance, false);
  assert.deepEqual(report.pad_differences.map(item => item.ref), ['D1']);
});

test('reports a pad offset when copper disagrees with the placement', () => {
  const report = run(
    [baseline, delivery, policy, 'examples/top-copper-shifted.gbr'],
    1,
  );
  assert.equal(report.status, 'different');
  assert.deepEqual(
    report.pad_differences.map(({ ref, kind }) => [ref, kind]),
    [['D1', 'pad_offset']],
  );
});

test('normalizes supported Gerber coordinates and rejects malformed coordinates', t => {
  const directory = mkdtempSync(join(tmpdir(), 'moonplacement-gerber-format-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const copper = join(directory, 'copper.gbr');
  const original = readFileSync('examples/top-copper.gbr', 'utf8');
  const trailing = original.replace('FSLAX46Y46', 'FSTAX46Y46')
    .replace(/([XY])([0-9]{8})/g, (_, axis, digits) =>
      axis + digits.padStart(10, '0').replace(/0+$/, ''))
    .replace('X0024Y0013D03*', 'X0024Y0013D02*\nD03*');
  assert.notEqual(trailing, original);
  assert.match(trailing, /D02\*\nD03\*/);
  writeFileSync(copper, trailing);
  const good = run([baseline, delivery, policy, copper], 0);
  assert.equal(good.pad_checked, 5);
  assert.deepEqual(good.pad_differences, []);
  for (const [text, message] of [
    [original.replace('X24000000Y13000000D03', 'XYD03'), /坐标缺少数值/],
    [original.replace('X24000000Y13000000D03', 'X24000000000Y13000000D03'), /FS 位宽/],
    [original.replace('FSLAX46Y46', 'FSLIX46Y46'), /增量坐标/],
    [original.replace('FSLAX46Y46', 'FSLAX46Y45'), /X\/Y 位宽/],
  ]) {
    writeFileSync(copper, text);
    const report = run([baseline, delivery, policy, copper], 64);
    assert.equal(report.status, 'input_error');
    assert.equal(report.field, copper);
    assert.match(report.message, message);
  }
});

test('writes an HTML report with a board map', t => {
  const directory = mkdtempSync(join(tmpdir(), 'moonplacement-html-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const target = join(directory, 'report.html');
  const report = run(
    [baseline, delivery, policy, 'examples/top-copper.gbr', '--html', target],
    0,
  );
  assert.equal(report.status, 'pass');
  const html = readFileSync(target, 'utf8');
  assert.match(html, /<svg/);
  assert.match(html, /MoonPlacement/);
});

test('invalid arguments and files return a structured input error', t => {
  const invalid = run([], 64);
  assert.equal(invalid.field, 'arguments');
  assert.equal(invalid.schema_version, 3);
  assert.equal(run([baseline, 'examples/missing.csv', policy], 64).field, 'examples/missing.csv');
  assert.equal(run([baseline, 'examples', policy], 64).field, 'examples');

  const directory = mkdtempSync(join(tmpdir(), 'moonplacement-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const invalidUtf8 = join(directory, '贴片坐标.csv');
  writeFileSync(invalidUtf8, Buffer.from([0xff, 0xfe]));
  assert.equal(run([baseline, invalidUtf8, policy], 64).field, invalidUtf8);
  const largePolicy = join(directory, 'large.json');
  writeFileSync(largePolicy, Buffer.alloc(65_537));
  assert.match(run([baseline, delivery, largePolicy], 64).message, /65536/);
});
