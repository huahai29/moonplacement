import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const mod = 'huahai29/moonplacement';
const moon = process.env.MOONPLACEMENT_MOON || 'moon';
const version = readFileSync('moon.mod', 'utf8').match(/^version = "([^"]+)"$/m)?.[1];
assert.ok(version, 'moon.mod must declare a version');
const parent = resolve('_build', 'release-consumer');
mkdirSync(parent, { recursive: true });
const work = mkdtempSync(join(parent, 'project-'));
const args = process.argv.slice(2);
assert.ok(args.length === 0 || (args.length === 2 && args[0] === '--unpacked'),
  'Usage: node tests/release-consumer.mjs [--unpacked directory]');
const local = args.length ? resolve(args[1]) : undefined;

function call(...params) {
  const result = spawnSync(moon, params, { cwd: work, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `moon ${params.join(' ')}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}

function put(name, text) {
  writeFileSync(join(work, name), text);
}

if (local) {
  const packaged = readFileSync(join(local, 'moon.mod'), 'utf8');
  assert.ok(packaged.includes(`name = "${mod}"`) && packaged.includes(`version = "${version}"`));
  const members = ['.', local.replaceAll('\\', '/')];
  put('moon.work', `members = ${JSON.stringify(members)}\n`);
}
put('moon.mod', local
  ? `name = "verification/moonplacement"\nimport { "${mod}@${version}", }\n`
  : 'name = "verification/moonplacement"\n');
const consumerPackage = `import { "${mod}" @mp, }\npkgtype(kind: "executable")\n`;
put('moon.pkg', consumerPackage);
put('main.mbt', readFileSync('examples/library/main.mbt.example', 'utf8'));
for (const example of ['panel', 'register']) {
  mkdirSync(join(work, example));
  put(`${example}/moon.pkg`, consumerPackage);
  put(`${example}/main.mbt`, readFileSync(`examples/library/${example}.mbt.example`, 'utf8'));
}
mkdirSync(join(work, 'cross-eda'));
put('cross-eda/moon.pkg', consumerPackage);
put('cross-eda/main.mbt', readFileSync('tests/cross-eda/main.mbt', 'utf8'));
if (!local) call('add', `${mod}@${version}`);

const backendReports = {};
for (const target of ['js', 'wasm-gc']) {
  const report = JSON.parse(call('run', '.', '--target', target));
  assert.equal(report.schema_version, 3);
  assert.equal(report.status, 'different');
  assert.equal(report.pad_status, 'not_requested');
  assert.equal(report.differences.length, 1);
  const [difference] = report.differences;
  assert.equal(difference.ref, 'D1');
  assert.equal(difference.kind, 'position');
  assert.ok(Math.abs(difference.distance_mm - 0.3) < 0.000001);
  const panel = JSON.parse(call('run', 'panel', '--target', target));
  assert.equal(panel.status, 'indeterminate');
  assert.equal(panel.reason, 'insufficient_pad_evidence');
  assert.deepEqual(panel.panel_cells, [{
    side: 'top', row: 2, column: 2, rows: 2, columns: 2, offset_x_mm: 20, offset_y_mm: 20,
  }]);
  assert.deepEqual(panel.needs_review, [{ ref: 'D1', side: 'top', evidence: 'copper_only' }]);
  const registration = JSON.parse(call('run', 'register', '--target', target));
  assert.ok(Math.abs(registration.rotation_deg - 90) < 1e-9);
  assert.ok(Math.abs(registration.translation_mm[0] - 5) < 1e-9);
  assert.ok(Math.abs(registration.translation_mm[1] + 3) < 1e-9);
  assert.equal(registration.inliers, 3);
  assert.ok(registration.rms_mm < 1e-9);
  backendReports[target] = { status: report.status, schema_version: report.schema_version,
    difference: { ref: difference.ref, kind: difference.kind, distance_mm: difference.distance_mm },
    panel, registration };
}
const hardware = resolve('examples/hardware/antmicro-usb-c-power-adapter');
const kicad = join(hardware, 'kicad-placement.csv');
const easyeda = join(hardware, 'easyeda-pro-placement.csv');
const policy = join(hardware, 'import-policy.json');
const copper = join(hardware, 'usb-c-power-adapter-B_Cu.gbr');

function shiftC17(path, columnIndex, original, shifted) {
  const data = readFileSync(path, 'utf8');
  const row = /^"C17",(.*)$/m.exec(data);
  assert.ok(row, `Missing C17 in ${path}`);
  // The pinned C17 rows have simple CSV fields. Verify the exact X field before editing.
  const fields = row[0].split(',');
  assert.equal(fields[columnIndex], original, `C17 X field changed in ${path}`);
  fields[columnIndex] = shifted;
  const filename = `shifted-${path === kicad ? 'kicad' : 'easyeda'}.csv`;
  put(filename, data.slice(0, row.index) + fields.join(',') + data.slice(row.index + row[0].length));
  return join(work, filename);
}

const crossEda = {};
for (const [label, baseline, delivery] of [
  ['original', kicad, easyeda],
  ['c17_shifted', shiftC17(kicad, 3, '88.950000', '89.250000'),
    shiftC17(easyeda, 5, '"88.95"', '"89.25"')],
]) {
  const report = JSON.parse(call('run', '--target', 'js', 'cross-eda', '--',
    baseline, delivery, policy, copper));
  const shifted = label === 'c17_shifted';
  assert.equal(report.status, shifted ? 'different' : 'pass');
  assert.deepEqual(report.differences, []);
  assert.equal(report.pad_status, 'complete');
  assert.equal(report.pad_checked, 44);
  assert.deepEqual(report.pad_sides, ['bottom']);
  const j1 = report.pad_evidence.find(item => item.ref === 'J1').evidence;
  assert.equal(j1.origin.status, 'corrected');
  assert.ok(j1.within_tolerance && Math.abs(j1.distance_mm) < 1e-9);
  assert.deepEqual(report.pad_differences.map(({ ref, kind }) => [ref, kind]),
    shifted ? [['C17', 'pad_offset']] : []);
  const c17 = report.pad_evidence.find(item => item.ref === 'C17').evidence;
  assert.equal(c17.within_tolerance, !shifted);
  assert.ok(Math.abs(c17.distance_mm - (shifted ? 0.3 : 0)) < 1e-9);
  crossEda[label] = { status: report.status, pad_checked: report.pad_checked,
    j1_distance_mm: j1.distance_mm, c17_distance_mm: c17.distance_mm };
}

const evidence = { module: mod, version, source: local ? 'unpacked' : 'mooncakes',
  toolchain: call('version', '--all').split(/\r?\n/).find(line => line.startsWith('moonc '))?.split(' (')[0],
  backends: backendReports, cross_eda_js: crossEda };
writeFileSync(join(parent, local ? 'unpacked.json' : 'mooncakes.json'), JSON.stringify(evidence, null, 2) + '\n');
console.log(`${mod}@${version} (${evidence.source}): JS and Wasm-GC consumer examples passed; JS cross-EDA verified 44 bottom placements and the 0.30 mm C17 shift`);
