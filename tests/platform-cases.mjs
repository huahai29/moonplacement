import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const tolerance = 1e-8;
const matrix = [
  ['normal', 'delivery-ok', 'policy', null, null, 0, 'pass'],
  ['differences', 'delivery-errors', 'policy', null, null, 1, 'different'],
  ['ambiguity', 'delivery-ok', 'policy-ambiguous', null, null, 2, 'indeterminate'],
  ['similarity', 'delivery-similarity', 'policy-similarity', null, null, 0, 'pass'],
  ['clearance', 'delivery-ok', 'policy', 'arc-clearance', null, 2, 'indeterminate'],
  ['panel-clean', 'delivery-ok', 'policy', 'panel-cell-2x2', '1,2', 0, 'pass'],
  ['panel-shifted', 'delivery-ok', 'policy', 'panel-cell-2x2', '2,2', 1, 'different'],
  ['panel-out-of-range', 'delivery-ok', 'policy', 'panel-cell-2x2', '3,1', 64, 'input_error'],
];

function record() {
  const out = resolve('_build');
  const cli = join(out, 'js', 'debug', 'build', 'cmd', 'main', 'main.js');
  const workspace = mkdtempSync(join(tmpdir(), '贴装 核对-'));
  try {
    const results = {};
    for (const [name, delivery, policy, layer, cell, exit, status] of matrix) {
      const inputs = ['examples/baseline.csv', `examples/${delivery}.csv`, `examples/${policy}.json`];
      if (layer) inputs.push(`examples/gerber/${layer}.gbr`);
      const paths = inputs.map((source, i) => {
        const path = join(workspace, ['基准.csv', '交付.csv', '配置.json', '顶层.gbr'][i]);
        copyFileSync(source, path);
        return path;
      });
      const html = join(workspace, `报告-${name}.html`);
      const args = [...paths, ...(cell ? ['--panel-cell', cell] : []), '--html', html];
      const run = spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
      assert.ifError(run.error);
      assert.equal(run.status, exit, `${name}: ${run.stdout}${run.stderr}`);
      const report = JSON.parse(run.stdout);
      assert.equal(report.status, status);
      if (exit === 64) {
        assert.equal(report.field, paths.at(-1));
        report.field = '顶层.gbr';
      } else {
        const saved = readFileSync(html, 'utf8');
        assert.match(saved, /<meta charset="utf-8">/);
        assert.match(saved, /铜层核对/);
        if (cell) assert.match(saved, /顶面拼板单元/);
      }
      if (name === 'panel-shifted') {
        assert.deepEqual(report.pad_differences.map(({ ref }) => ref), ['D1']);
        assert.ok(Math.abs(report.pad_differences[0].distance_mm - 0.3) < 0.0001);
      }
      results[name] = { exit, report };
    }
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, 'platform-cases.json'), JSON.stringify({ platform: process.platform, results }, null, 2) + '\n');
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
}

function compare(left, right, path) {
  if (typeof left === 'number' && typeof right === 'number' &&
      !Number.isInteger(left) && !Number.isInteger(right)) {
    assert.ok(Math.abs(left - right) <= tolerance, `${path}: ${left} vs ${right}`);
  } else if (Array.isArray(left) && Array.isArray(right)) {
    assert.equal(left.length, right.length, path);
    left.forEach((value, i) => compare(value, right[i], `${path}[${i}]`));
  } else if (left && right && typeof left === 'object' && typeof right === 'object' &&
      !Array.isArray(left) && !Array.isArray(right)) {
    assert.deepEqual(Object.keys(left).sort(), Object.keys(right).sort(), path);
    for (const [key, value] of Object.entries(left)) compare(value, right[key], `${path}.${key}`);
  } else {
    assert.equal(left, right, path);
  }
}

if (process.argv[2] === 'record') {
  record();
} else if (process.argv[2] === 'compare' && process.argv.length === 5) {
  const [linux, windows] = process.argv.slice(3).map(path => JSON.parse(readFileSync(path, 'utf8')));
  assert.equal(linux.platform, 'linux');
  assert.equal(windows.platform, 'win32');
  const expected = matrix.map(([name]) => name).sort();
  assert.deepEqual(Object.keys(linux.results).sort(), expected);
  compare(linux.results, windows.results, 'cases');
  console.log(`${expected.length} CLI cases agree on Linux and Windows`);
} else {
  throw new Error('Usage: platform-cases.mjs record | compare linux.json windows.json');
}
