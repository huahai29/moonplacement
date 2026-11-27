const byId = id => document.getElementById(id);
const form = byId('audit-form');
const run = byId('run');
const demo = byId('demo');
const state = byId('result-state');
const detail = byId('result-detail');
const metrics = byId('metrics');
const downloads = byId('downloads');
const frame = byId('report-frame');
const exportNotice = byId('export-notice');
const previewNotice = byId('preview-notice');
const referenceForm = byId('reference-form');
const referenceInput = byId('reference-input');
const referenceResult = byId('reference-result');
const cell = byId('use-cell');
const row = byId('row');
const column = byId('column');
const empty = { name: '', text: '' };
const textDecoder = new TextDecoder('utf-8', { fatal: true });
const exportNames = {
  json: 'moonplacement-report.json',
  html: 'moonplacement-report.html',
  receipt: 'moonplacement-receipt.json',
};
let auditWorker;
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
  insufficient_pad_evidence: '有器件的铜层证据需复查，详情见报告。',
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

function askWorker(message, timeoutMessage) {
  const worker = auditWorker;
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      clearTimeout(timer);
      worker.onmessage = worker.onerror = worker.onmessageerror = null;
    };
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(timeoutMessage));
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
    try { worker.postMessage(message); }
    catch (error) {
      cleanup();
      reject(error);
    }
  });
}

function setState(kind, message, notes = '') {
  state.dataset.kind = kind;
  state.textContent = message;
  detail.textContent = notes;
  detail.hidden = !notes;
}

function closeAudit() {
  auditWorker?.terminate();
  auditWorker = undefined;
}

function setBusy(busy) {
  run.disabled = demo.disabled = byId('reference-submit').disabled = busy;
  for (const button of downloads.querySelectorAll('button')) button.disabled = busy;
}

function resetResult() {
  closeAudit();
  frame.hidden = metrics.hidden = downloads.hidden = previewNotice.hidden = exportNotice.hidden = true;
  referenceForm.hidden = referenceResult.hidden = true;
  referenceForm.reset();
  referenceResult.replaceChildren();
  frame.removeAttribute('srcdoc');
}

function showPreview(html, notice) {
  frame.hidden = !html;
  if (html) frame.srcdoc = html;
  else frame.removeAttribute('srcdoc');
  previewNotice.textContent = notice ?? '';
  previewNotice.hidden = !notice;
}

function show({ report, summary, html, preview_notice }) {
  if (report) {
    closeAudit();
    setState(report.status, resultLabels.input_error, `${report.field} · ${report.message}`);
    return;
  }
  const worst = summary.worst_pad;
  const failedLayers = summary.failed_layers.map(side => side === 'top' ? '顶铜核验失败' : '底铜核验失败');
  const finding = worst ? `${worst.ref} 铜层偏差 ${worst.distance_mm.toFixed(2)} mm`
    : (failedLayers.length ? '' : reasons[summary.reason]);
  setState(summary.status, resultLabels[summary.status],
    [finding, ...failedLayers].filter(Boolean).join(' · '));
  byId('table-count').textContent = String(summary.table_count);
  byId('pad-count').textContent = String(summary.pad_count);
  byId('checked-count').textContent = String(summary.pad_checked);
  metrics.hidden = downloads.hidden = referenceForm.hidden = false;
  showPreview(html, preview_notice);
  byId('download-receipt').hidden = !summary.receipt_available;
}

const sides = { top: '顶面', bottom: '底面' };
const findings = {
  missing: '送厂表漏件', missing_baseline: '基准表缺件', missing_both: '两表均缺件',
  extra: '送厂表多件', value: '器件值差异', package: '封装差异', side: '板面差异', swapped: '位号调换',
};
const copperReasons = {
  possible_clearance: '存在可能影响焊盘的清除图形',
  repeated_reference: '多个拼板或块实例使用相同位号',
  pad_origin_review: '封装原点需复查',
};
const formatMeasure = value => value.toLocaleString('zh-CN', { maximumFractionDigits: 6 });

function findingDescription(item) {
  if (item.kind === 'position') return `位置偏差 ${formatMeasure(item.distance_mm)} mm`;
  if (item.kind === 'angle') return `角度偏差 ${formatMeasure(item.delta_deg)}°`;
  if (item.kind === 'swapped') return `位号调换 · ${item.with}`;
  const title = findings[item.kind] ?? item.kind;
  if (item.kind === 'side') return `${title} · ${sides[item.baseline]} → ${sides[item.delivery]}`;
  if (item.kind === 'value' || item.kind === 'package') return `${title} · ${item.baseline} → ${item.delivery}`;
  return title;
}

function copperDescription(copper) {
  switch (copper.status) {
    case 'by_reference':
      return `铜层偏差 ${formatMeasure(copper.distance_mm)} mm${copper.within_tolerance ? '，在容差内' : '，超过容差'}`;
    case 'copper_only': return '附近有铜，位号归属未知';
    case 'unverified': {
      const reason = copper.origin_status === 'pose_mismatch' ? '板面或基准角度与原点校正规则不符'
        : (copperReasons[copper.reason] ?? '缺少可用的焊盘证据');
      return copper.source ? `${reason} · ${copper.source}` : reason;
    }
    default: return '此位号没有铜层核验记录';
  }
}

function showReference(reference) {
  referenceResult.replaceChildren();
  if (!reference.found) {
    referenceResult.textContent = `${reference.ref} 不在此次核对范围内。`;
    return;
  }
  const heading = document.createElement('h3');
  heading.textContent = reference.ref;
  const location = document.createElement('p');
  const cells = reference.panels.map(cell => `${sides[cell.side]}第 ${cell.row} 行第 ${cell.column} 列`);
  location.textContent = [`基准 ${sides[reference.baseline_side] ?? '缺件'}`,
    `送厂 ${sides[reference.delivery_side] ?? '缺件'}`, ...cells].join(' · ');
  const list = document.createElement('ul');
  const entries = reference.differences.length ? reference.differences.map(findingDescription) : ['坐标表无差异记录'];
  entries.push(copperDescription(reference.copper));
  for (const entry of entries) {
    const item = document.createElement('li');
    item.textContent = entry;
    list.append(item);
  }
  referenceResult.append(heading, location, list);
}

async function findReference(event) {
  event.preventDefault();
  const reference = referenceInput.value.trim();
  if (!auditWorker || run.disabled || !reference) return;
  setBusy(true);
  referenceResult.hidden = false;
  referenceResult.textContent = '正在查找…';
  try {
    const result = await askWorker({ action: 'lookup', reference }, '位号查询超时，请重新核对。');
    showReference(result.reference);
    showPreview(result.html, result.preview_notice);
  } catch (error) {
    closeAudit();
    referenceForm.hidden = downloads.hidden = true;
    referenceResult.textContent = error.message;
  } finally {
    setBusy(false);
  }
}

async function exportReport(format) {
  if (!auditWorker || run.disabled) return;
  setBusy(true);
  exportNotice.textContent = '正在生成下载文件…';
  exportNotice.hidden = false;
  try {
    const { file } = await askWorker({ action: 'export', format }, '生成报告超过 30 秒。请重新核对，或使用命令行工具导出。');
    const url = URL.createObjectURL(file);
    const link = document.createElement('a');
    link.href = url;
    link.download = exportNames[format];
    link.hidden = true;
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
    exportNotice.hidden = true;
  } catch (error) {
    closeAudit();
    referenceForm.hidden = downloads.hidden = true;
    exportNotice.textContent = error.message;
  } finally {
    setBusy(false);
  }
}

async function check(useDemo) {
  if (run.disabled) return;
  setBusy(true);
  resetResult();
  setState('idle', '正在核对…');
  try {
    if (typeof Worker !== 'function') {
      throw new Error('此浏览器无法在后台运行核对。请使用当前版本的浏览器或命令行。');
    }
    const input = await files(useDemo);
    auditWorker = new Worker(new URL('./worker.mjs', import.meta.url), { type: 'module' });
    show(await askWorker({ action: 'audit', input }, '核对超过 30 秒。可尝试只核对一个拼板单元，或使用命令行。'));
  } catch (error) {
    closeAudit();
    setState('input_error', '无法完成核对', error.message);
  } finally {
    setBusy(false);
  }
}

form.addEventListener('submit', event => {
  event.preventDefault();
  void check(false);
});
demo.addEventListener('click', () => void check(true));
referenceForm.addEventListener('submit', event => void findReference(event));
for (const format of Object.keys(exportNames)) {
  byId(`download-${format}`).addEventListener('click', () => void exportReport(format));
}
