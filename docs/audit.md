# 核对规则

## 输入配置

两个 CSV 都应为 UTF-8，接受 BOM、引号转义和带换行的引用字段。关键列可以重排，额外列会跳过。位号忽略首尾空白和大小写，规范化后的重复位号会报错。每份 CSV 最多 8 MiB、100,000 个器件、256 列，配置最多 64 KiB。坐标和角度的原始数值范围为 ±1,000,000。

| 配置 | 含义 |
| --- | --- |
| `baseline`、`delivery` | 各自填写 `unit`（`mm`、`in` 或 `mil`）及 `bottom_x`（`direct` 保留，`negated` 对底面 X 取反，送厂表还可填 `auto`） |
| `angle_sign` | 该表原始角度换成共同方向时乘以 `1` 或 `-1` |
| `top_angle_offset_deg`、`bottom_angle_offset_deg` | 该表对应板面在乘以 `angle_sign` 后加上的角度，范围 ±360° |
| `anchors` | 3～64 个已确认身份、板面和位置的基准位号 |
| `rotation` | 送厂表换到基准表的逆时针旋转角，可填字符串 `"0"`、`"90"`、`"180"`、`"270"` 或 `"auto"`。已知文件方向相同就用 `"0"` |
| `anchor_tolerance_mm` | 每个基准点允许的最大二维残差，大于 0 且不超过 100 mm |
| `position_tolerance_mm` | 对齐后器件允许的二维距离，大于 0 且不超过 100 mm |
| `angle_tolerance_deg` | 器件允许的最小圆周角差，大于 0 且不超过 180° |

底面 X 与角度约定分别配置。例如 KiCad 的底面 X 取反选项改动 X 坐标，角度仍按原角度字段导出。输入必须使用可换算的器件中心和角度零位。合并表应使用同一面板、同一版次及一致的 DNP 筛选规则。参见 [KiCad 位置文件导出](https://docs.kicad.org/9.0/en/cli/cli.html#pcb-export-position-file)和[嘉立创贴片文件说明](https://jlcpcb.com/help/article/pick-place-file-for-pcb-assembly)。

## 怎么对齐

1. 将两表坐标换成毫米，应用各表的底面 X 约定。自动模式会尝试两种底面约定，有底面数据时两种都保留为候选。
2. 按配置尝试四分之一圈旋转。所有基准须存在于两张表且板面一致。两表各自基准的最长连线以及至少一个点到该连线的垂距都要大于两倍基准容差，避免用近共线点确认变换。
3. 每个候选先算出各基准点单独对齐所需的平移量。用这些平移量的最小包围圆圆心作为全板平移，使最大二维残差最小。实作枚举由一至三个点确定的圆心并核对所有基准，计算使用双精度。每个基准点的实测残差都在容差内，候选才通过。通过的候选多于一个时保留歧义。参见 [最小包围圆的支撑点定义](https://doc.cgal.org/latest/Bounding_volumes/classCGAL_1_1Min__circle__2.html)。
4. 两张表始终按位号比较漏件、多件和错面。只有找到唯一候选时才比较位置和角度。两张表无差异且有未参与拟合的器件时，结果才为 `pass`。

角度差按「送厂角度经方向、零位和整板旋转校正后减基准角度」计算，归入 `[-180°, 180°)`。错面的器件只报板面差异，因为它的坐标和角度可能用了另一套板面约定。形变、比例误差、器件专属封装零位以及任意角旋转超出此工具的对齐范围。

## JSON 报告 v2

- `status` 和 `reason` 表示结果及无法确认的原因。原因包括基准缺失或错面（`invalid_anchors`）、基准点接近共线（`degenerate_baseline_anchors`）、没有候选符合容差（`no_matching_frame`）、有多个候选（`ambiguous_frame`）、无独立核对点（`no_independent_components`）。
- `frame` 是唯一选中的变换，可能为空。包含 `rotation_deg`、`delivery_bottom_x`、平移向量 `delivery_to_baseline_mm`、最大基准残差 `max_anchor_error_mm`。
- `candidate_frames` 列出通过基准检查的候选。`rejected_frames` 用 `anchor_tolerance_exceeded` 标记超出容差的候选，并附该候选的 `frame`。`degenerate_delivery_anchors` 表示该底面约定下的基准分布退化，此时只给出约定和原因。
- 每个算出平移的 `frame` 都含 `anchor_residuals` 和 `worst_anchor_refs`。逐点残差按配置里的基准顺序给出位号、对齐后送厂点减基准点的 `delta_x_mm`、`delta_y_mm`、二维距离 `distance_mm` 和是否在基准容差内。`worst_anchor_refs` 包含达到最大残差的全部位号。残差可用于定位复核对象，同一组基准可能有多个并列最差点。
- `differences` 记录器件差异。即使整体状态为 `indeterminate`，仍列出已确认的 `missing`、`extra` 和 `side`。有唯一对齐变换时，也列出 `position` 和 `angle`。
- `anchor_issues` 单独记录基准异常。`anchor_missing_baseline`、`anchor_missing_delivery`、`anchor_missing_both` 分别表示缺在基准表、送厂表或两表，`anchor_side` 表示板面不一致。
- 报告同时记录两表行数、基准位号和本次容差。输入无效时输出 `input_error`、`field` 和 `message`。

从 v1 迁移时，在 `anchor_issues` 读取原先位于 `differences` 中的 `anchor_*`。输入配置、CLI 调用方式与退出码保持一致。

## 源码入口

| 文件 | 职责 |
| --- | --- |
| `csv.mbt`、`placement.mbt` | CSV 读取、位号与关键字段校验 |
| `policy.mbt` | 配置解析及输入范围 |
| `alignment.mbt`、`minimax.mbt` | 单位、底面约定、四分之一圈旋转及最小最大残差平移 |
| `audit.mbt` | 独立核对与报告 |
| `cmd/main/main.mbt` | 读取文件并按结果设置退出码 |

库入口是 `read_placements`、`read_policy` 和 `audit`。CSV 或配置问题抛出 `InputError`。库不调用 KiCad 或远程服务。
