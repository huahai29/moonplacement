import { expect, test } from '@playwright/test';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const example = path => resolve('../examples', path);

async function download(page, label, filename) {
  const [file] = await Promise.all([page.waitForEvent('download'), page.getByRole('button', { name: label }).click()]);
  expect(file.suggestedFilename()).toBe(filename);
  return readFile(await file.path(), 'utf8');
}

test('D1 sample downloads both report formats and a receipt for the same audit', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await page.getByRole('button', { name: '运行 D1 示例' }).click();
  await expect(page.getByRole('status')).toHaveText('发现差异');
  await expect(page.locator('#result-detail')).toHaveText('D1 铜层偏差 0.30 mm');
  const preview = page.frameLocator('#report-frame');
  await expect(preview.getByText('顶面拼板单元：第 2 行，第 2 列。')).toBeVisible();
  await expect(preview.getByRole('cell', { name: 'D1', exact: true })).toBeVisible();
  const report = JSON.parse(await download(page, '下载 JSON', 'moonplacement-report.json'));
  expect(report.schema_version).toBe(3);
  expect(report.differences).toEqual([]);
  expect(report.pad_differences).toEqual([expect.objectContaining({ ref: 'D1', kind: 'pad_offset' })]);
  const html = await download(page, '下载 HTML', 'moonplacement-report.html');
  expect(html).toContain('<meta charset="utf-8">');
  expect(html).toContain('第 2 行，第 2 列');
  expect(html).toContain('<h2>原始 JSON</h2>');

  const receipt = JSON.parse(await download(page, '下载核验凭据', 'moonplacement-receipt.json'));
  const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
  const engine = await readFile('../_build/js/release/build/bridge/bridge.js');
  expect(receipt.schema).toBe('moonplacement.receipt.v1');
  expect(receipt.producer).toMatchObject({ host: 'web', build_sha256: sha256(engine) });
  expect(receipt.report).toEqual(report);
  expect(receipt.inputs).toEqual(await Promise.all([
    ['policy', 'policy.json'],
    ['baseline', 'baseline.csv'],
    ['delivery', 'delivery-ok.csv'],
    ['top_gerber', 'gerber/panel-cell-2x2.gbr'],
  ].map(async ([role, path]) => {
    const bytes = await readFile(example(path));
    return { role, bytes: bytes.length, sha256: sha256(bytes) };
  })));
  expect(errors).toEqual([]);
});

test('local files stay in the browser and invalid UTF-8 is reported', async ({ page }) => {
  const requests = [];
  page.on('request', request => requests.push(request));
  await page.goto('/');
  await page.locator('#baseline').setInputFiles(example('baseline.csv'));
  await page.locator('#delivery').setInputFiles(example('delivery-ok.csv'));
  await page.locator('#policy').setInputFiles(example('policy.json'));
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('核对通过');
  expect(requests.every(request => request.method() === 'GET' &&
    (!request.url().startsWith('http') || request.url().startsWith('http://127.0.0.1:')) &&
    !request.url().includes('/samples/'))).toBe(true);

  await page.locator('#delivery').setInputFiles({
    name: '坏文件.csv', mimeType: 'text/csv', buffer: Buffer.from([0xff, 0xfe]),
  });
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('无法完成核对');
  await expect(page.locator('#result-detail')).toHaveText('坏文件.csv 不是有效的 UTF-8 文件。');
  await expect(page.getByRole('button', { name: '下载 JSON' })).toBeHidden();
  await expect(page.getByRole('button', { name: '下载核验凭据' })).toBeHidden();
});

test('duplicate policy fields keep the workbench from showing an audit verdict', async ({ page }) => {
  await page.goto('/');
  await page.locator('#baseline').setInputFiles(example('baseline.csv'));
  await page.locator('#delivery').setInputFiles(example('delivery-ok.csv'));
  const original = await readFile(example('policy.json'), 'utf8');
  const duplicate = original.trimEnd().replace(/}$/, ',"position_tolerance_mm":2}');
  await page.locator('#policy').setInputFiles({
    name: 'duplicate.json', mimeType: 'application/json', buffer: Buffer.from(duplicate),
  });
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('输入有误');
  await expect(page.locator('#result-detail')).toContainText('position_tolerance_mm · 配置项重复');
  await expect(page.locator('#report-frame')).toBeHidden();
  await expect(page.getByRole('button', { name: '下载 JSON' })).toBeHidden();
});

test('the original KiCad and EasyEDA exports use the uploaded placement profile', async ({ page }) => {
  const fixture = file => example(`hardware/antmicro-usb-c-power-adapter/${file}`);
  await page.goto('/');
  await page.locator('#baseline').setInputFiles(fixture('kicad-placement.csv'));
  await page.locator('#delivery').setInputFiles(fixture('easyeda-pro-placement.csv'));
  await page.locator('#policy').setInputFiles(fixture('import-policy.json'));
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('核对通过');
  const preview = page.frameLocator('#report-frame');
  await expect(preview.getByRole('heading', { name: '导入口径' })).toBeVisible();
  await expect(preview.getByRole('listitem').filter({ hasText: 'Ref X / Ref Y' })).toContainText('TP1');
  const report = JSON.parse(await download(page, '下载 JSON', 'moonplacement-report.json'));
  expect(report.baseline_count).toBe(97);
  expect(report.delivery_count).toBe(97);
  expect(report.placement_import.delivery.excluded_refs).toHaveLength(27);
  expect(report.placement_import.delivery.footprint_prefix).toBe('antmicro-footprints:');

  await page.locator('#top').setInputFiles(fixture('usb-c-power-adapter-F_Cu.gbr'));
  await page.locator('#bottom').setInputFiles(fixture('usb-c-power-adapter-B_Cu.gbr'));
  await page.getByRole('button', { name: '开始核对' }).click();
  const corrected = preview.getByRole('listitem').filter({ hasText: 'J1（底面）' });
  await expect(corrected).toContainText('原点偏移已校正');
  await expect(corrected).toContainText('原始距离 2.2663');
  await expect(corrected).toContainText('校正后');
  await expect(page.getByRole('status')).toHaveText('无法确认');
  await expect(page.locator('#result-detail')).toHaveText('顶铜核验失败');
  const copper = JSON.parse(await download(page, '下载 JSON', 'moonplacement-report.json'));
  expect(copper.pad_checked).toBe(44);
  expect(copper.pad_differences).toEqual([]);
  expect(copper.pad_evidence.find(({ ref }) => ref === 'J1').evidence.distance_mm).toBeLessThan(1e-9);

  const policy = JSON.parse(await readFile(fixture('import-policy.json'), 'utf8'));
  policy.pad_origins = [{ ref: 'J1', mode: 'review', source: '复查 <J1>' }];
  await page.locator('#policy').setInputFiles({
    name: 'review.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(policy)),
  });
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(preview.getByRole('listitem').filter({ hasText: 'J1（底面）' })).toContainText('原因：复查 <J1>');
  await expect(page.getByRole('status')).toHaveText('无法确认');
});

test('the workbench reports a failed top layer alongside independently verified bottom copper', async ({ page }) => {
  await page.goto('/');
  await page.locator('#baseline').setInputFiles(example('baseline.csv'));
  await page.locator('#delivery').setInputFiles(example('delivery-ok.csv'));
  await page.locator('#policy').setInputFiles(example('policy.json'));
  await page.locator('#top').setInputFiles({
    name: 'broken.gbr', mimeType: 'text/plain', buffer: Buffer.from('%FSLAX46Y46*%%MOINVALID*%M02*'),
  });
  const bottom = example('gerber/bottom-copper-matching.gbr');
  await page.locator('#bottom').setInputFiles(bottom);
  const run = page.getByRole('button', { name: '开始核对' });
  await run.click();
  await expect(page.getByRole('status')).toHaveText('无法确认');
  await expect(page.locator('#result-detail')).toHaveText('顶铜核验失败');
  const preview = page.frameLocator('#report-frame');
  await expect(preview.getByText(/顶铜核验失败.*MO 单位/)).toBeVisible();
  await expect(preview.getByText('底铜已核验全部位号（3 / 3）')).toBeVisible();

  const shifted = (await readFile(bottom, 'utf8')).replace('X25000000', 'X25300000');
  await page.locator('#bottom').setInputFiles({
    name: 'shifted.gbr', mimeType: 'text/plain', buffer: Buffer.from(shifted),
  });
  await run.click();
  await expect(page.getByRole('status')).toHaveText('发现差异');
  await expect(page.locator('#result-detail')).toHaveText('C7 铜层偏差 0.30 mm · 顶铜核验失败');
  const audit = JSON.parse(await download(page, '下载 JSON', 'moonplacement-report.json'));
  expect(audit.pad_layers.map(({ status }) => status)).toEqual(['failed', 'complete']);
  const receipt = JSON.parse(await download(page, '下载核验凭据', 'moonplacement-receipt.json'));
  expect(receipt.report).toEqual(audit);
  expect(receipt.inputs.map(({ role }) => role)).toEqual(['policy', 'baseline', 'delivery', 'top_gerber', 'bottom_gerber']);
});

test('an unavailable digest leaves the ordinary reports usable', async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(window.crypto, 'subtle', { value: undefined }));
  await page.goto('/');
  await page.getByRole('button', { name: '运行 D1 示例' }).click();
  await expect(page.getByRole('status')).toHaveText('发现差异');
  await expect(page.getByRole('button', { name: '下载 JSON' })).toBeVisible();
  await expect(page.getByRole('button', { name: '下载 HTML' })).toBeVisible();
  await expect(page.getByRole('button', { name: '下载核验凭据' })).toBeHidden();
});

test('100,000 components keep the initial worker response small and export all findings on demand', async ({ page }) => {
  test.setTimeout(90_000);
  await page.addInitScript(() => {
    const BrowserWorker = window.Worker;
    window.workerActions = [];
    window.workerResponses = [];
    window.Worker = class extends BrowserWorker {
      constructor(...args) {
        super(...args);
        this.addEventListener('message', ({ data }) => {
          window.workerResponses.push(data.file ? { fileBytes: data.file.size }
            : { bytes: new Blob([JSON.stringify(data)]).size, keys: Object.keys(data).sort() });
        });
      }
      postMessage(message) {
        window.workerActions.push(message.action);
        super.postMessage(message);
      }
    };
  });
  await page.goto('/');
  const anchors = ['Ref,PosX,PosY,Rot,Side', 'R1,0,0,0,top', 'C1,20,0,0,top',
    'R2,0,20,0,top', 'R3,20,20,0,bottom'];
  const count = 99_996;
  for (const [id, x] of [['baseline', 10], ['delivery', 11]]) {
    const lines = [...anchors];
    for (let i = 0; i < count; i++) {
      lines.push(`P${String(i).padStart(5, '0')},${x},10,0,top`);
    }
    await page.locator(`#${id}`).setInputFiles({ name: `${id}.csv`, mimeType: 'text/csv',
      buffer: Buffer.from(lines.join('\n')) });
  }
  const settings = JSON.parse(await readFile(example('policy.json'), 'utf8'));
  settings.delivery = settings.baseline;
  await page.locator('#policy').setInputFiles({ name: 'policy.json', mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(settings)) });
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('发现差异', { timeout: 32_000 });
  await expect(page.locator('#table-count')).toHaveText(String(count));
  const preview = page.frameLocator('#report-frame');
  await expect(preview.getByText('仅显示前 32 项（共 99996 项）。')).toBeVisible();
  await expect(preview.getByText('板图含 100000 个器件。下载 HTML 查看完整板图。')).toBeVisible();
  await expect(preview.getByRole('row')).toHaveCount(33);
  await expect(preview.getByRole('heading', { name: '原始 JSON' })).toHaveCount(0);
  expect(await page.evaluate(() => window.workerActions)).toEqual(['audit']);
  const [initial] = await page.evaluate(() => window.workerResponses);
  expect(initial.keys).toEqual(['html', 'summary']);
  expect(initial.bytes).toBeLessThan(12 * 1024);

  const report = JSON.parse(await download(page, '下载 JSON', 'moonplacement-report.json'));
  expect(report.status).toBe('different');
  expect(report.differences).toHaveLength(count);
  expect(report.differences.at(-1)).toMatchObject({ ref: 'P99995', distance_mm: 1 });
  const html = await download(page, '下载 HTML', 'moonplacement-report.html');
  expect(html.includes('<td>P99995</td>')).toBe(true);
  expect(html.includes('<h2>原始 JSON</h2>')).toBe(true);
  expect(await page.evaluate(() => window.workerActions)).toEqual(['audit', 'export', 'export']);
  const [, jsonFile, htmlFile] = await page.evaluate(() => window.workerResponses);
  expect(jsonFile.fileBytes).toBeGreaterThan(1024 * 1024);
  expect(htmlFile.fileBytes).toBeGreaterThan(1024 * 1024);
  console.log(`100,000 components: initial response ${initial.bytes} bytes; downloaded JSON ${jsonFile.fileBytes} bytes and HTML ${htmlFile.fileBytes} bytes`);
});

test('mobile panel selection shows the Gerber error and clears a stale result', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByRole('button', { name: '运行 D1 示例' }).click();
  await expect(page.getByRole('status')).toHaveText('发现差异');
  await page.locator('#baseline').setInputFiles(example('baseline.csv'));
  await page.locator('#delivery').setInputFiles(example('delivery-ok.csv'));
  await page.locator('#policy').setInputFiles(example('policy.json'));
  await page.locator('#top').setInputFiles(example('gerber/panel-cell-2x2.gbr'));
  await page.getByRole('checkbox', { name: '按 SR 拼板单元核对' }).check();
  await page.locator('#column').fill('3');
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('输入有误');
  await expect(page.locator('#result-detail')).toContainText('拼板单元超出范围');
  await expect(page.locator('#report-frame')).toBeHidden();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390);
});

test('rejects a layer explicitly declared as bottom copper in the top slot', async ({ page }) => {
  await page.goto('/');
  await page.locator('#baseline').setInputFiles(example('baseline.csv'));
  await page.locator('#delivery').setInputFiles(example('delivery-ok.csv'));
  await page.locator('#policy').setInputFiles(example('policy.json'));
  const top = await readFile(example('gerber/panel-cell-2x2.gbr'), 'utf8');
  await page.locator('#top').setInputFiles({
    name: 'declared-bottom.gbr',
    mimeType: 'text/plain',
    buffer: Buffer.from(top.replace('Copper,L1,Top', 'Copper,L2,Bot')),
  });
  await page.getByRole('checkbox', { name: '按 SR 拼板单元核对' }).check();
  await page.getByRole('button', { name: '开始核对' }).click();
  await expect(page.getByRole('status')).toHaveText('输入有误');
  await expect(page.locator('#result-detail')).toContainText('declared-bottom.gbr');
  await expect(page.locator('#result-detail')).toContainText('.FileFunction 与顶层铜输入不符');
  await expect(page.locator('#report-frame')).toBeHidden();
});

test('a browser without Workers displays a usable error', async ({ page }) => {
  await page.addInitScript(() => { window.Worker = undefined; });
  await page.goto('/');
  await page.getByRole('button', { name: '运行 D1 示例' }).click();
  await expect(page.getByRole('status')).toHaveText('无法完成核对');
  await expect(page.locator('#result-detail')).toContainText('命令行');
  await expect(page.getByRole('button', { name: '运行 D1 示例' })).toBeEnabled();
});
