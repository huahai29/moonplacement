import { audit_files, export_audit, receiptBuildSha256 } from './engine.mjs';

const PREVIEW_BYTES = 256 * 1024;

function audit({ baseline, delivery, policy, top, bottom, row, column }) {
  const files = Object.entries({ policy, baseline, delivery, top_gerber: top, bottom_gerber: bottom })
    .filter(([, file]) => file.name);
  const fingerprints = files.every(([, file]) => file.sha256)
    ? JSON.stringify(files.map(([role, { bytes, sha256 }]) => ({ role, bytes, sha256 })))
    : '';
  const result = JSON.parse(audit_files(
    baseline.text, baseline.name, delivery.text, delivery.name, policy.text,
    top.text, top.name, bottom.text, bottom.name, row, column,
    fingerprints, receiptBuildSha256,
  ));
  if (result.html && new Blob([result.html]).size > PREVIEW_BYTES) {
    delete result.html;
    result.preview_notice = '预览超过大小上限。下载报告可查看完整明细。';
  }
  return result;
}

self.onmessage = ({ data }) => {
  try {
    if (data.action === 'audit') {
      self.postMessage(audit(data.input));
    } else {
      const content = export_audit(data.format);
      if (!content) throw new Error('Missing audit export');
      const type = data.format === 'html' ? 'text/html;charset=utf-8' : 'application/json';
      self.postMessage({ file: new Blob([content], { type }) });
    }
  } catch {
    self.postMessage({ error: data.action === 'audit'
      ? '核对程序未能完成。请检查文件，或使用命令行工具复查。'
      : '生成报告失败。请重新核对，或使用命令行工具导出。' });
  }
};
