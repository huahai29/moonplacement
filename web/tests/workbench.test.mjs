import { expect, test } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const example = path => resolve('../examples', path);

test('D1 sample renders the panel evidence and downloads both report formats', async ({ page }) => {
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto('/');
  await page.getByRole('button', { name: '运行 D1 示例' }).click();
  await expect(page.getByRole('status')).toHaveText('发现差异');
  await expect(page.locator('#result-detail')).toHaveText('D1 铜层偏差 0.30 mm');
  const preview = page.frameLocator('#report-frame');
  await expect(preview.getByText('顶面拼板单元：第 2 行，第 2 列。')).toBeVisible();
  await expect(preview.getByRole('cell', { name: 'D1', exact: true })).toBeVisible();
  for (const [label, filename] of [
    ['下载 JSON', 'moonplacement-report.json'],
    ['下载 HTML', 'moonplacement-report.html'],
  ]) {
    const [file] = await Promise.all([page.waitForEvent('download'), page.getByRole('link', { name: label }).click()]);
    expect(file.suggestedFilename()).toBe(filename);
    const contents = await readFile(await file.path(), 'utf8');
    if (filename.endsWith('.json')) {
      const report = JSON.parse(contents);
      expect(report.schema_version).toBe(3);
      expect(report.differences).toEqual([]);
      expect(report.pad_differences).toEqual([expect.objectContaining({ ref: 'D1', kind: 'pad_offset' })]);
    } else {
      expect(contents).toContain('<meta charset="utf-8">');
      expect(contents).toContain('第 2 行，第 2 列');
    }
  }
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
  await expect(page.getByRole('link', { name: '下载 JSON' })).toBeHidden();
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

test('a browser without Workers displays a usable error', async ({ page }) => {
  await page.addInitScript(() => { window.Worker = undefined; });
  await page.goto('/');
  await page.getByRole('button', { name: '运行 D1 示例' }).click();
  await expect(page.getByRole('status')).toHaveText('无法完成核对');
  await expect(page.locator('#result-detail')).toContainText('命令行');
  await expect(page.getByRole('button', { name: '运行 D1 示例' })).toBeEnabled();
});
