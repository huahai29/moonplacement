# MoonPlacement 0.3.0

- 在线工作台可以按位号查两表差异、板面、拼板单元与铜层复查原因，并在预览板图里标出器件。
- Gerber 保留 X2 文件、光圈和对象属性以及块光圈调用来源。选定拼板单元时，位号与引脚归属保持一致。
- 原生读取 KiCad 和嘉立创 EDA 坐标表，支持双面铜层分别报告失败，以及按位号或封装修正贴装原点。

## 安装与验证

```sh
moon add huahai29/moonplacement@0.3.0
```

项目验证工具链为 `moonc v1.0.0-rc1+3c0520448`。在发行源码根目录运行 `node tests/release-consumer.mjs`，从 Mooncakes 安装固定版本并复跑库示例。JS 实板案例使用 KiCad、嘉立创原始坐标表和底铜，核验 44 个底面位号。同时改动两张表的 C17 横坐标 0.30 mm 后，两表比较仍一致，铜层报告应指出 C17 偏离 0.30 mm。

## 升级配置

JSON 核对报告仍为 v3。升级后，配置中的重复键、未知字段会报 `input_error` 并给出字段路径。请按路径删除重复项或修正字段名。核验凭据中的模块版本更新为 `0.3.0`。

[公共 API](api.md) · [跨 EDA 实板案例](cross-eda.md) · [Gerber 命令覆盖](gerber-acceptance.md)
