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
| `alignment` | 可选，默认 `enumerate`。填 `rigid`、`similarity` 或 `affine` 时改用注册引擎从基准点拟合连续变换；写入后 `rotation` 不再参与 |
| `anchor_tolerance_mm` | 每个基准点允许的最大二维残差，大于 0 且不超过 100 mm |
| `position_tolerance_mm` | 对齐后器件允许的二维距离，大于 0 且不超过 100 mm |
| `angle_tolerance_deg` | 器件允许的最小圆周角差，大于 0 且不超过 180° |
| `pad_tolerance_mm` | 可选，铜层质心与送厂坐标之间允许的距离，缺省 0.1 mm |

底面 X 与角度约定分别配置。例如 KiCad 的底面 X 取反选项改动 X 坐标，角度仍按原角度字段导出。输入必须使用可换算的器件中心和角度零位。合并表应使用同一面板、同一版次及一致的 DNP 筛选规则。参见 [KiCad 位置文件导出](https://docs.kicad.org/9.0/en/cli/cli.html#pcb-export-position-file)和[嘉立创贴片文件说明](https://jlcpcb.com/help/article/pick-place-file-for-pcb-assembly)。

## 怎么对齐

1. 将两表坐标换成毫米，应用各表的底面 X 约定。自动模式会尝试两种底面约定，有底面数据时两种都保留为候选。
2. 所有基准须存在于两张表且板面一致。两表各自基准的最长连线以及至少一个点到该连线的垂距都要大于两倍基准容差，避免用近共线点确认变换。
3. 在 `enumerate` 模式下，按 `rotation` 指定的角度计算候选。`"auto"` 会尝试四种角度。每个候选先算出各基准点单独对齐所需的平移量，再用这些平移量的最小包围圆圆心作为全板平移，使最大二维残差最小。实作枚举由一至三个点确定的圆心并核对所有基准，计算使用双精度。每个基准点的实测残差都在容差内，候选才通过。通过的候选多于一个时保留歧义。参见 [最小包围圆的支撑点定义](https://doc.cgal.org/latest/Bounding_volumes/classCGAL_1_1Min__circle__2.html)。
4. 在 `rigid`、`similarity` 或 `affine` 模式下，用连续变换拟合代替第 3 步。刚体和相似模型使用闭式最小二乘，仿射模型求解三参数法方程。确定性 RANSAC 枚举刚体和相似的两点样本、仿射的三点样本，按基准容差选出一致集合，再用集合内的点重新拟合。一致集合至少有 3 个点，且至多丢掉 1 个基准，候选才通过。刚体估计旋转和平移，相似模型增加均匀尺度，仿射模型还允许错切及各向异性缩放。
5. 两张表始终按位号比较漏件、多件和错面。只有找到唯一候选时才比较位置和角度。两张表无差异且有未参与拟合的器件时，如果没有要求铜层核验，结果为 `pass`。

角度差按「送厂角度经方向、零位和整板旋转校正后减基准角度」计算，归入 `[-180°, 180°)`。错面的器件只报板面差异，因为它的坐标和角度可能用了另一套板面约定。器件专属封装零位和任意形变仍超出此工具的对齐范围；连续旋转和比例误差在注册引擎模式下由变换本身吸收。

库调用方可用 `register` 直接拟合两组点，读取旋转角、尺度、平移、残差、均方根误差和一致集合。

## 铜层核对

命令行可追加顶层、或按顶层加底层的顺序追加两个 Gerber（RS-274X）文件。工具只核验传入的板面，把送厂坐标映射回基准坐标系，再与铜层比较。Gerber 和基准坐标表应使用同一原点和坐标方向。

- 坐标支持 `FS` 声明的绝对坐标及前零、尾零省略。`MO` 必须声明毫米或英寸，省略的 X/Y 轴沿用当前位置，单独的 `D03` 在当前位置放置焊盘。增量坐标、两轴位宽不一致和无效坐标会返回 `input_error`。见 [Gerber 格式规范](https://www.ucamco.com/en/gerber)。
- 标准 `C`/`R`/`O`/`P` 支持同心圆孔。光圈宏支持单圆、中心线矩形、向量线、多边形轮廓、正多边形、热焊盘以及 KiCad 圆角矩形组合。部分实心外形可开多个互不接触的圆孔。孔内区域不提供铜证据，也不清除孔下已有的铜。焊盘归属优先用 X2 `TO.P` 的位号，其次用 `TO.C`。`TD` 支持按属性名清除。其他命令与范围见 [Gerber 2024.05 验收](gerber-acceptance.md)。
- 有位号归属时，计算该器件暗色闪光焊盘的面积加权中心，与送厂坐标比较。差值超过 `pad_tolerance_mm` 记为 `pad_offset`。该中心不一定等于不对称封装的贴装原点；用此结果判断贴装偏位前应确认原点定义。
- 无归属时，只提供「附近有铜」或「未核验」线索。附近铜可由受支持的闪光、圆弧描线和区域提供。后绘制的清除圆弧按实际弧段及线宽筛查，焊盘用外接圆估计，可能相交的位号标为未核验。含弧区域按轮廓判断。一个铜区内的独立轮廓取并集，折返路径围出的孔保持透明。圆弧离散误差带内保守处理。超出当前范围的宏会返回输入错误。块光圈 `AB` 和拼板 `SR` 可展开几何。块内已标注的焊盘保留位号；单闪光块可以使用调用处的位号。多对象块不从调用处猜测每个焊盘的归属。若同一位号随拼板被复制，可使用 `--panel-cell` 或拆分文件后再核验。
- 两份表都带 `Val` / `Package` 列时，还会逐位号比较型号与封装，差异记为 `value` 与 `package`。

有唯一变换时，只要确认了一项差异，结论即为 `different`。若无差异但所请求的铜层缺少位号证据，结论为 `indeterminate`。没有要求铜层核验时，继续沿用两表判定。

## 拼板单元

`--panel-cell "行,列"` 按 1 起算，行沿 Gerber 的 +Y，列沿 +X。只处理每层恰好一组可分隔的 `SR` 网格；仅用 `AB` 手工排版或多个 `SR` 网格的文件需要先拆分。设计表和送厂表使用第一块 (1,1) 的坐标系。

- 单元范围由顶层 SR 基础图形的包围范围和步距确定，边界取相邻单元之间的中线。与选中单元相交但跨界的图形、相切或重叠的单元都报输入错误；只有一行或一列的方向不限范围。
- 同时传顶、底铜层时，行列数和有效步长必须一致，底层沿用顶层边界。选中区域内的对象平移回 (1,1)，保留原绘制顺序，含 SR 外单独写出的对象。
- JSON 的 `panel_cells` 逐层给出行列、网格大小和毫米偏移。未选单元时为空。单元内依然存在歧义的块位号会保留 `repeated_reference`。不会自动给整板表格补单元编号。

## JSON 报告 v3

- `status` 和 `reason` 表示结果及无法确认的原因。原因包括基准缺失或错面（`invalid_anchors`）、基准点接近共线（`degenerate_baseline_anchors`）、没有候选符合容差（`no_matching_frame`）、有多个候选（`ambiguous_frame`）、无独立核对点（`no_independent_components`）和铜层位号证据不足（`insufficient_pad_evidence`）。
- `frame` 是唯一选中的变换，可能为空。包含 `rotation_deg`、`scale`、`delivery_bottom_x`、平移向量 `delivery_to_baseline_mm`、最大基准残差 `max_anchor_error_mm`。枚举模式下 `scale` 恒为 `1`，`rotation_deg` 为 90 的整数倍；注册引擎模式下两者都是连续估计值。
- `candidate_frames` 列出通过基准检查的候选。`rejected_frames` 用 `anchor_tolerance_exceeded` 标记超出容差的候选，并附该候选的 `frame`。`degenerate_delivery_anchors` 表示该底面约定下的基准分布退化，此时只给出约定和原因。
- 每个算出平移的 `frame` 都含 `anchor_residuals` 和 `worst_anchor_refs`。逐点残差按配置里的基准顺序给出位号、对齐后送厂点减基准点的 `delta_x_mm`、`delta_y_mm`、二维距离 `distance_mm`、是否在基准容差内以及是否进入一致集合的 `inlier`。`worst_anchor_refs` 包含达到最大残差的全部位号。残差可用于定位复核对象，同一组基准可能有多个并列最差点。
- `differences` 记录器件差异。即使整体状态为 `indeterminate`，仍列出已确认的 `missing`、`extra`、`side`，以及 `value` 和 `package`。有唯一对齐变换时，也列出 `position` 和 `angle`。某位号缺失、而一个新位号恰好落在它的期望位置时，按改名处理并记为 `swapped`，`with` 给出新位号，不再重复记为 `missing` 和 `extra`。
- `pad_differences` 记录可归属到位号的 `pad_offset`。`pad_checked` 只计有归属的器件，包含超限器件；`pad_sides` 是用户传入的板面。`pad_status` 为 `not_requested`、`skipped`（无唯一对齐，等同 `pad_skipped: true`）、`incomplete`（缺位号证据）或 `complete`（证据齐全，可能仍有超限）。
- `pad_evidence` 按位号和板面记录 `by_reference`、`copper_only` 或 `unverified`。`by_reference` 同时给出焊盘数、距离及是否在容差内。可能被后绘制的清除对象影响时，`unverified` 带 `reason: "possible_clearance"` 和下述定位线索。拼板内重复位号返回 `reason: "repeated_reference"`。`pad_warnings` 保留板面诊断，普通圆弧和远处的清除对象可与 `pad_status: "complete"` 共存。

  - `clearance.pad` 给出一块候选受影响焊盘的引脚（X2 未提供时为 `null`）、中心坐标和对象编号。
  - `clearance.object` 给出一个后绘制清除对象的编号、类型（`flash`、`line`、`arc`、`region`）及保守包围范围。每个位号只保留一组线索，便于复查，不表示已经确认交点，也不枚举所有影响。
  - `object_number` 从 1 起，按当前铜层展开后的绘制顺序编号；选择拼板单元后只对该单元的对象编号。坐标以毫米计，选定拼板时已平移到第一个单元的坐标系。`statement_number` 是从 1 起的解析命令序号（光圈宏定义计一条，含注释命令），不是文本行号；块内对象指向定义中的命令，区域指向结束命令。
- `anchor_issues` 单独记录基准异常。`anchor_missing_baseline`、`anchor_missing_delivery`、`anchor_missing_both` 分别表示缺在基准表、送厂表或两表，`anchor_side` 表示板面不一致。
- 报告同时记录两表行数、基准位号和本次容差。输入无效时输出 `input_error`、`field` 和 `message`。

从 v2 迁移时，改用 `pad_evidence` 判断是否有焊盘归属，不再依据 `no_copper`。调用方式不变，原本证据不足仍通过的输入现在返回退出码 2。从 v1 迁移时，在 `anchor_issues` 读取原先位于 `differences` 的 `anchor_*`。

## 源码入口

| 文件 | 职责 |
| --- | --- |
| `csv.mbt`、`placement.mbt` | CSV 读取、位号与关键字段校验 |
| `policy.mbt` | 配置解析及输入范围 |
| `geom.mbt` | 焊盘形状、多边形面积/质心/包含测试 |
| `gerber.mbt` | RS-274X 子集解析与 X2 属性归属 |
| `padcheck.mbt` | 位号归属、焊盘中心比较和附近有铜的线索 |
| `transform.mbt` | 二维仿射变换类型与旋转、尺度、平移的读取 |
| `register.mbt` | 刚体、相似、仿射的闭式估计与确定性 RANSAC |
| `report.mbt` | 自包含 HTML 报告与 SVG 板面示意图 |
| `alignment.mbt`、`minimax.mbt` | 单位、底面约定、四分之一圈旋转及最小最大残差平移 |
| `audit.mbt` | 独立核对与报告 |
| `cmd/main/main.mbt` | 读取文件并按结果设置退出码 |

库入口是 `read_placements`、`read_policy`、`audit`、`register`、`parse_gerber`、`check_pads` 和 `render_html`。CSV、配置或 Gerber 问题抛出 `InputError` / `GerberError`。库不调用 KiCad 或远程服务。
