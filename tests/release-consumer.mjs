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
mkdirSync(join(work, 'panel'));
put('panel/moon.pkg', consumerPackage);
put('panel/main.mbt', readFileSync('examples/library/panel.mbt.example', 'utf8'));
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
  backendReports[target] = { status: report.status, schema_version: report.schema_version,
    difference: { ref: difference.ref, kind: difference.kind, distance_mm: difference.distance_mm },
    panel };
}
const evidence = { module: mod, version, source: local ? 'unpacked' : 'mooncakes',
  toolchain: call('version', '--all').split(/\r?\n/).find(line => line.startsWith('moonc '))?.split(' (')[0],
  backends: backendReports };
writeFileSync(join(parent, local ? 'unpacked.json' : 'mooncakes.json'), JSON.stringify(evidence, null, 2) + '\n');
console.log(`${mod}@${version} (${evidence.source}): JS and Wasm-GC found the D1 offset and the panel review item`);
