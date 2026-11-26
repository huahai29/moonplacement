const byId = id => document.getElementById(id);
const form = byId('audit-form');
const run = byId('run');
const demo = byId('demo');
const state = byId('result-state');
const detail = byId('result-detail');
const metrics = byId('metrics');
const downloads = byId('downloads');
const frame = byId('report-frame');
const cell = byId('use-cell');
const row = byId('row');
const column = byId('column');
const empty = { name: '', text: '' };
const textDecoder = new TextDecoder('utf-8', { fatal: true });
const resultLabels = {
  pass: '核对通过',
  different: '发现差异',
  indeterminate: '无法确认',
  input_error: '输入有误',
};
const reasons = {
  invalid_anchors: '请检查基准位号是否在两张表中，且位于同一板面。',
  degenerate_baseline_anchors: '请在设计表中选用分布更开的基准器件。',
  no_matching_frame: '没有候选配准满足基准容差。',
  ambiguous_frame: '多个配准候选满足容差。请检查基准件和方向约定。',
  insufficient_pad_evidence: '有器件缺少可归属到位号的铜层证据。',
  no_independent_components: '表中的器件都参加了配准，缺少独立核对点。',
};

cell.addEventListener('change', () => {
  byId('cell-fields').hidden = !cell.checked;
  row.disabled = column.disabled = !cell.checked;
});

async function decodeFile(name, buffer) {
  let text;
  try { text = textDecoder.decode(buffer); }
  catch { throw new Error(`${name} 不是有效的 UTF-8 文件。`); }
  let sha256;
  try {
    const hash = await globalThis.crypto.subtle.digest('SHA-256', buffer);
    sha256 = Array.from(new Uint8Array(hash), byte => byte.toString(16).padStart(2, '0')).join('');
  } catch {
    // Older/insecure contexts can still run a report without a receipt.
  }
  return { name, text, bytes: buffer.byteLength, sha256 };
}

async function localFile(id, maxBytes) {
  const file = byId(id).files[0];
  if (!file) return empty;
  if (file.size > maxBytes) throw new Error(`${file.name} 超过 ${maxBytes.toLocaleString('zh-CN')} 字节。`);
  return decodeFile(file.name, await file.arrayBuffer());
}

async function getAsset(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error('工作台资源加载失败，请刷新后重试。');
  return response;
}

async function sample(name) {
  return decodeFile(name, await (await getAsset('./samples/' + name)).arrayBuffer());
}

async function files(useDemo) {
  if (useDemo) {
    const [baseline, delivery, policy, top] = await Promise.all([
      sample('baseline.csv'), sample('delivery-ok.csv'), sample('policy.json'), sample('panel-cell-2x2.gbr'),
    ]);
    return { baseline, delivery, policy, top, bottom: empty, row: 2, column: 2 };
  }
  const schema = await (await getAsset('./contract.json')).json();
  const limits = schema['x-moonplacement-input-bytes'];
  const [baseline, delivery, policy, top, bottom] = await Promise.all([
    localFile('baseline', limits.placement), localFile('delivery', limits.placement),
    localFile('policy', limits.policy), localFile('top', limits.gerber), localFile('bottom', limits.gerber),
  ]);
  return { baseline, delivery, policy, top, bottom,
    row: cell.checked ? row.valueAsNumber : 0, column: cell.checked ? column.valueAsNumber : 0 };
}

function calculate(input) {
  return new Promise((resolve, reject) => {
    if (typeof Worker !== 'function') {
      reject(new Error('此浏览器无法在后台运行核对。请使用当前版本的浏览器或命令行。'));
      return;
    }
    const worker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    const cleanup = () => {
      clearTimeout(timer);
      worker.terminate();
    };
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error('核对超过 30 秒。可尝试只核对一个拼板单元，或使用命令行。'));
    }, 30_000);
    worker.onmessage = ({ data }) => {
      cleanup();
      if (data.error) reject(new Error(data.error));
      else resolve(data);
    };
    worker.onerror = worker.onmessageerror = () => {
      cleanup();
      reject(new Error('后台核对程序无法运行，请刷新后重试。'));
    };
    worker.postMessage(input);
  });
}

function setState(kind, message, notes = '') {
  state.dataset.kind = kind;
  state.textContent = message;
  detail.textContent = notes;
  detail.hidden = !notes;
}

function resetResult() {
  for (const id of ['download-json', 'download-html', 'download-receipt']) {
    const link = byId(id);
    if (link.hasAttribute('href')) URL.revokeObjectURL(link.href);
    link.removeAttribute('href');
  }
  frame.hidden = metrics.hidden = downloads.hidden = true;
  frame.removeAttribute('srcdoc');
}

function show({ report, html, receipt }) {
  if (report.status === 'input_error') {
    setState(report.status, resultLabels.input_error, `${report.field} · ${report.message}`);
    return;
  }
  const offsets = report.pad_differences.filter(item => item.kind === 'pad_offset');
  const worst = offsets.reduce((best, item) => (!best || item.distance_mm > best.distance_mm ? item : best), null);
  const failedLayers = (report.pad_layers ?? []).filter(layer => layer.status === 'failed')
    .map(layer => layer.side === 'top' ? '顶铜核验失败' : '底铜核验失败');
  const finding = worst ? `${worst.ref} 铜层偏差 ${worst.distance_mm.toFixed(2)} mm`
    : (failedLayers.length ? '' : reasons[report.reason]);
  setState(report.status, resultLabels[report.status],
    [finding, ...failedLayers].filter(Boolean).join(' · '));
  byId('table-count').textContent = String(report.differences.length);
  byId('pad-count').textContent = String(report.pad_differences.length);
  byId('checked-count').textContent = String(report.pad_checked);
  metrics.hidden = downloads.hidden = frame.hidden = false;
  frame.srcdoc = html;
  byId('download-json').href = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2) + '\n'],
    { type: 'application/json' }));
  byId('download-html').href = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }));
  const receiptLink = byId('download-receipt');
  receiptLink.hidden = !receipt;
  if (receipt) {
    receiptLink.href = URL.createObjectURL(new Blob([JSON.stringify(receipt, null, 2) + '\n'],
      { type: 'application/json' }));
  }
}

async function check(useDemo) {
  if (run.disabled) return;
  run.disabled = demo.disabled = true;
  resetResult();
  setState('idle', '正在核对…');
  try {
    show(await calculate(await files(useDemo)));
  } catch (error) {
    setState('input_error', '无法完成核对', error.message);
  } finally {
    run.disabled = demo.disabled = false;
  }
}

form.addEventListener('submit', event => {
  event.preventDefault();
  void check(false);
});
demo.addEventListener('click', () => void check(true));
