> **Historical record (2026-10-15).** Statements here about a zipc/flate 0.2.0 version conflict with mbtexcel, "mbtexcel integration not done" or 166/166 workspace counts describe that earlier state. They were resolved in the 2026-10-18 integration candidate (flate 0.9.0, no zipc; acceptance JS 65/65, Wasm GC 65/65, same-module mbtexcel 0.3.0 PASS). See README.md for the current state.

# ODS 第二轮优化：精度、负零与明确损失说明

本轮基于本地候选 c675449e9bde26cf245441326371323f02d71bb5，保留原有有界公共 API。没有推送、发布或重新申报；这不是任意 ODS 无损往返承诺。

## 实际改动

1. **非零下溢拒绝**：原读取器会把 `1e-9999` 等非零输入变为 0。现在拒绝并给出单元格位置，不能以“有限数值”掩盖数据变化。真实最小次正规数仍可接受，`0e-9999` 仍为合法零。
2. **数值精度变化逐格提示**：将源十进制表示与实际 writer 输出作精确的十进制规范化比较。`9007199254740993` 等被 binary64 舍入后产生 `NUMBER_PRECISION_CHANGED`，保留 sheet/row/col；公式数值缓存也适用。`1.00`、`+1E+2` 等等价写法不误报。此比较不提供任意精度运算，也不保证 0.1 可在二进制内部精确表示；它检测源十进制值与实际输出十进制值的差异。
3. **ODS 负零修复**：原 writer 的普通数值字符串化会把 -0 写成 0。现在复用同一数值输出函数，保留 -0 的符号，已对普通单元格、公式缓存及合并场景验证。
4. **损失说明更具体**：实际存在且未保留的 styles.xml、meta.xml、settings.xml、manifest.rdf 和缩略图产生 `PACKAGE_PART_DROPPED`；content.xml 中实际存在的格式定义产生 `DOCUMENT_FORMATTING_DROPPED`。已有逐格格式和公式缓存说明保留。非空 named ranges 等未支持结构继续拒绝，错误现在指明结构的命名空间名称。
5. **独立资源上限**：数值输入限 1,024 个 UTF-16 单元，精度提示仅展示前 96 个字符，避免长数值通过重复单元格放大诊断文本。原 ZIP 实际解压、XML 深度、表格展开、总文字和 8,192 条诊断上限保留。

## 类型与不支持内容

日期仍限有效 Gregorian YYYY-MM-DD；空字符串、空值和只含空格的字符串仍独立。样式不会授权忽略超链接或注释等未支持语义；带值的 covered cell 不会被静默丢弃。非空 named ranges、无缓存公式、未知内容仍拒绝。数据模式必须显式接受，元数据和格式不承诺原样保存。

## 跨格式桥接边界

仍采用两个进程的公共 API 桥接，未解决 mbtexcel 与 zipc 的 flate 同模块版本冲突。

本轮发现 JSON/XLSX 路径仍会丢失负零符号：桥接现在使用明确的负零标记传递源信息，实际调用 mbtexcel 后检查读取值的符号。mbtexcel 输出 0 时逐格产生 `NUMBER_SIGNED_ZERO_CHANGED`，不会用普通数值相等代替符号验证。核心 ODS 的 -0 修复不等于 XLSX 无损。

精度变化提示从 ODS 导入经 typed JSON 保留到 XLSX 报告。公式仍默认拒绝；明确 cache-only 时才丢弃并逐格说明。日期 1900 边界、空字符串/空值和工作表顺序验证保留。

## 可复核证据

- 将本轮十项回归放到原 c675449 候选运行，61 项中 54 通过、7 失败。日志位于 evidence/typed-reader-round2-20261015/baseline-new-regressions-js.log；这七项包含真实缺陷与新增诊断/资源契约，并非宣称七个独立核心 bug。
- 修改后 MoonODS 核心 JS、Wasm GC 各 61/61；含依赖的完整工作区各 166/166。检查、构建、独立公共消费者、Python 类型语义核对及实际 LibreOfficeDev 原生回存均再次运行通过。
- 独立审查在复制的 60 项基线上追加七项，JS、Wasm GC 各 67/67；与本轮 61 项不是同一测试集合，不相加。其额外覆盖数值边界、诊断上限、重复单元格定位、负零公式缓存/合并及真实 ZIP 元数据提示。
- 两进程桥接重新实际 write/read XLSX；精度提示和负零损失说明另行检查。其证据位于配套 ods-mbtexcel-public-bridge.tar.gz。

当前源码绑定和最终日志仍在 evidence/typed-reader-20261015/review-validation.json。该目录的当前日志对应第二轮；第一轮日志仍可从完整 Git 历史的 c675449 取回。

## 尚未通过的门槛

稳定版 LibreOffice、GUI、其他办公软件、更多外部 producer、新输出 schema 验证和旧锁定工具链的完整发行验收仍未完成。当前 SDK 不符合旧 TOOLCHAIN.lock，旧完整验收仍然阻塞，没有放宽标准。测试和明确诊断也不等于评审已经认可增量价值。
