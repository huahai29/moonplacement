import { audit_files } from './engine.mjs';

self.onmessage = ({ data: { baseline, delivery, policy, top, bottom, row, column } }) => {
  try {
    const result = audit_files(
      baseline.text, baseline.name, delivery.text, delivery.name, policy.text,
      top.text, top.name, bottom.text, bottom.name, row, column,
    );
    self.postMessage(JSON.parse(result));
  } catch {
    self.postMessage({ error: '核对程序未能完成。请检查文件，或使用仓库里的命令行工具复查。' });
  }
};
