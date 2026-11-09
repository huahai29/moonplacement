import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const bin = '_build/js/debug/build/cmd/main/main.js';
const baseline = 'examples/baseline.csv';
const delivery = 'examples/delivery-ok.csv';
const policy = 'examples/policy.json';

function run(args, expectedExit) {
  const result = spawnSync(process.execPath, [bin, ...args], { encoding: 'utf8' });
  assert.ifError(result.error);
  assert.equal(result.status, expectedExit, result.stderr || result.stdout);
  return JSON.parse(result.stdout);
}

test('normalizes inches, origin shift and bottom X', () => {
  const report = run([baseline, delivery, policy], 0);
  assert.equal(report.schema_version, 1);
  assert.equal(report.status, 'pass');
  assert.equal(report.frame.delivery_bottom_x, 'negated');
  assert.ok(Math.abs(report.frame.delivery_to_baseline_mm.x - 5) < 0.00002);
  assert.ok(Math.abs(report.frame.delivery_to_baseline_mm.y - 7) < 0.00002);
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
});

test('invalid arguments and files return a structured input error', t => {
  assert.equal(run([], 64).field, 'arguments');
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
