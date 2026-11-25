import { audit_files, receiptBuildSha256 } from './engine.mjs';

self.onmessage = ({ data: { baseline, delivery, policy, top, bottom, row, column } }) => {
  try {
    const files = Object.entries({ policy, baseline, delivery, top_gerber: top, bottom_gerber: bottom })
      .filter(([, file]) => file.name);
    const fingerprints = files.every(([, file]) => file.sha256)
      ? JSON.stringify(files.map(([role, { bytes, sha256 }]) => ({ role, bytes, sha256 })))
      : '';
    const result = audit_files(
      baseline.text, baseline.name, delivery.text, delivery.name, policy.text,
      top.text, top.name, bottom.text, bottom.name, row, column,
      fingerprints, receiptBuildSha256,
    );
    self.postMessage(JSON.parse(result));
  } catch {
    self.postMessage({ error: '核对程序未能完成。请检查文件，或使用仓库里的命令行工具复查。' });
  }
};
