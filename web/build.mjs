import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const target = '_build/workbench';
const build = '_build/js/release/build';
mkdirSync(join(target, 'samples'), { recursive: true });
for (const file of ['index.html', 'workbench.mjs', 'worker.mjs', 'style.css']) {
  copyFileSync(join('web', file), join(target, file));
}
const engine = readFileSync(join(build, 'bridge', 'bridge.js'));
const engineSha256 = createHash('sha256').update(engine).digest('hex');
writeFileSync(join(target, 'engine.mjs'),
  Buffer.concat([engine, Buffer.from(`\nexport const receiptBuildSha256 = "${engineSha256}";\n`)]));
for (const file of ['baseline.csv', 'delivery-ok.csv', 'policy.json', 'gerber/panel-cell-2x2.gbr']) {
  copyFileSync(join('examples', file), join(target, 'samples', file.split('/').at(-1)));
}

const run = spawnSync(process.execPath, [join(build, 'cmd/main/main.js'), '--report-schema'], { encoding: 'utf8' });
assert.ifError(run.error);
assert.equal(run.status, 0, run.stderr || run.stdout);
const schema = JSON.parse(run.stdout);
assert.deepEqual(schema, JSON.parse(readFileSync('docs/接口契约.json', 'utf8')));
writeFileSync(join(target, 'contract.json'), JSON.stringify(schema));
console.log(`Built ${target}`);
