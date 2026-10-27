# 0.4.0 读取兼容：有限富文本与空白尾行

相对已发布 0.3.1，0.4.0 增加下列有界读取子集。默认仍须显式 `read_ods(bytes, allow_formatting_loss=true)`；扩展类型和基础格式保留另有独立选项，见[迁移说明](release-0.4.0.zh-CN.md)。

## 用途和边界

- 支持 `text:p` 中嵌套 `text:span`；段落和 span 仅接受 `text:style-name`，内部仅接受文字、同类 span、`text:s`、`text:tab`、`text:line-break`。不扩展为任意富文本；链接、脚本、未知节点和其他属性继续拒绝。
- 按输入次序拼接文字，保留空格、tab、换行及段落分隔。数值、布尔、日期和公式缓存仍以类型属性为准，数字的显示文本不保存。每个受影响单元格报告 `RICH_TEXT_FORMATTING_DROPPED`，含表名及从零起的行列；样式和文本分段会丢失。
- 只省略物理上全空的尾部连续行。先计入有效前缀、尾行最大宽度及剩余行/网格预算；全部能放下时保留，放不下时省略整个纯空尾部并报告 `EMPTY_TAIL_ROWS_DROPPED`。例如 1000 行有效数据加 24 空行保留；加 25 空行则只保留前 1000 行，不移动数据。
- 完整位于保留区域的合并仍保留；跨省略边界的合并拒绝。带值（包括显式空字符串）、公式、注释、覆盖单元格或未知属性的行不能当空尾删除；中间空洞不省略。
- 不提高 1024 行、128 列、单表 65536 网格、工作簿 262144 网格和原有文本/XML/ZIP预算。完全空的巨大尾部省略后，Sheet 仍采用现有最小 1×1 空表约定。

## 实际验证与复现

Mac 原生 pinned SDK 0.10.15 对最终实现完成四后端各 119/119、最小控制及独立消费者运行；生成接口同步后再次验证零 Git diff。早期云工具链的 Wasm/Wasm GC 控制失败不计作项目运行失败；历史 JS 106 项结果不冒充当前测试总数。远端精确 head CI 与 registry 消费按本次版本回执另列。

已有可用 SDK、锁定依赖和验证依赖时：

```sh
moon test --target js -j 1 --deny-warn . tests/consumer
moon check --target js -j 1 --deny-warn
moon build --target js -j 1 --deny-warn
python3 scripts/verify_reader_compat.py --moon /path/to/moon \
  --soffice /path/to/existing/soffice --output /tmp/moonods-reader-compat
```

脚本不安装软件、不联网、不发布。要求新输出目录；逐条记录命令、时间、预期/实际退出码及输入摘要，并独立检查 CSV/ODS 类型、值与富文本损失。负例检查输入和两个旧输出均不变。

实际 LibreOffice 为 **25.2.3.2 520(Build:2)**，使用 headless 本机进程进行保存；验证了真实生成的 span 文件、MoonODS 导出、LibreOffice 回存后再读及原有固定类型样本。新 `rich-text.fods` 为完全合成、MIT 来源，不能称为官方业务表格。该版 LibreOffice 从 FODS 转换时消除了源 tab/换行；脚本对直接合成 ODS 验证 tab/换行保留，对 LibreOffice 实际输出另做比较，不声称办公软件转换无损。

还实际验证了 LibreOffice/core 固定提交 `528ba1172ce7f2193db9297a3dac0bc4da7cd9d9` 的 [basic-cell-content.ods](https://github.com/LibreOffice/core/blob/528ba1172ce7f2193db9297a3dac0bc4da7cd9d9/sc/qa/unit/data/ods/basic-cell-content.ods)：B2 文本、B3 数值 12345、B4 文本、B5 数值 0 及导出再读。文件 10552 字节，SHA256 `634fe14c4daaf4e3e15db2dd3b72ba0deabb52d95a05d0f95764006c838ba0dc`。可用脚本的 `--upstream-fixture /path/basic-cell-content.ods` 复验；不随本项目重新分发该二进制，不改标 MIT，其上游 MPL-2.0/历史 Apache 来源边界见原固定夹具说明。

没有验证 Excel、GUI/打印排版、任意富文本、通用公式重算、并发或崩溃恢复。数据型读取允许样式损失，不适合保真办公文档编辑。

## 容量闭环与常见结构补强

- 修复自身 100×100 普通数值表被逐格格式诊断耗尽预算的问题。四类高频损失（格式、富文本、精度、公式缓存）按每个表、每类保留前 32 次完整诊断，后续用 `原代码_SUMMARY` 给出精确额外次数及首末额外坐标。不是静默截断，8192 条总硬上限未变。需要每个位置完整审计的应用应拒绝 SUMMARY 或对原始输入另做审计。
- 连续空格写为带 `text:c` 的单个节点；不再把 Text 同时完整写进属性和段落。相邻相同的非公式单元格和覆盖格可使用 ODF 重复计数；合并锚点、公式单元格不合并压缩。Empty 与 Text("")、正负零保持不同表示。
- `to_ods` 在构造 ZIP 前拒绝超过读取配置的 4 MiB 总解压条目或 XML 深度/节点预算的输出。原来的 16 MiB `content_xml` 是检查性 XML 接口，不保证其所有结果都能成为可读回的包。某些合法网格/文本组合仍会明确拒绝写出；不提高解析器安全上限。
- `table-header-rows`/`table-rows`、`table-header-columns`/`table-columns` 仅支持无属性、直接行/列子节点的形式，保持数据位置，表头打印/重复元数据单独报告损失。未知分组或隐藏/脚本等属性不自动接受。
- 实际 LibreOffice 回存给合并覆盖格添加 `table:style-name`。现在保留覆盖关系并定位报告样式损失；覆盖格中值、公式或正文仍拒绝。列宽、行高、单元格数字格式的损失消息细分种类并指出源样式名，不冒称已保真读回。
