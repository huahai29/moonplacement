import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';

export const padCenterToleranceMm = 0.001;
export const injectedOffsetMm = 0.30;

export function syncMarkdownSection(file, id, lines, write) {
  const start = `<!-- ${id}:start -->`;
  const end = `<!-- ${id}:end -->`;
  const document = readFileSync(file, 'utf8').replaceAll('\r\n', '\n');
  const from = document.indexOf(start);
  const to = document.indexOf(end, from);
  assert.ok(from >= 0 && to > from, `${file}: ${id} markers missing`);
  const expected = [start, '', ...lines, '', end].join('\n');
  if (write) {
    writeFileSync(file, document.slice(0, from) + expected + document.slice(to + end.length));
  } else {
    assert.equal(document.slice(from, to + end.length), expected, `${file}: ${id} is stale`);
  }
}
