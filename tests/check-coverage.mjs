import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const budget = JSON.parse(readFileSync(new URL('./coverage-budget.json', import.meta.url), 'utf8'));
const summary = readFileSync(process.argv[2], 'utf8');
const entries = new Map([...summary.matchAll(/^([^:\r\n]+): (\d+)\/(\d+)\r?$/gm)]
  .map(([, file, covered, total]) => [file, [Number(covered), Number(total)]]));
for (const [file, minimum] of Object.entries(budget)) {
  assert.ok(entries.has(file), `Coverage summary is missing ${file}`);
  const [covered, total] = entries.get(file);
  const percent = 100 * covered / total;
  assert.ok(total > 0 && percent >= minimum,
    `${file}: ${percent.toFixed(2)}%, below the ${minimum}% budget`);
  console.log(`${file}: ${percent.toFixed(2)}% (minimum ${minimum}%)`);
}
