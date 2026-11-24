import { mkdtempSync, renameSync, rmdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';

// Each CLI invocation gets a new output path. Keep the stable fixture for
// artifact collection, replacing it only after the whole invocation passes.
export function regenerateHtml(target, run) {
  const staging = mkdtempSync(join(dirname(target), '.test-html-'));
  const output = join(staging, 'report.html');
  try {
    const result = run(output);
    renameSync(output, target);
    return result;
  } finally {
    rmSync(output, { force: true });
    rmdirSync(staging);
  }
}
