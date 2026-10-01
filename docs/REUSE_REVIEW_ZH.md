# MoonODS 复用价值复核（AI 辅助技术事实）

复核日期：2026-10-01。用户提供的 LogLens 初审经历是提交记录/MVP完整性和场景过窄问题，不应误写为测试或许可不通过。本次依据这些经验检查 MoonODS 的可复用性；不代表官方已认可生态价值，不生成可冒充人工撰写的最终申报书。

## 不同领域的完整消费路径

独立模块 `moonods-audit/independent-consumer` 位于 `fixtures/reuse-consumer`，模块依赖声明为 `sundaysebasidian-byte/moonods@0.1.0`。模块只用公共 Workbook/Sheet/Cell/Value/Style API。下面的生成代码处理调用方传入的数组，示例数据都是合成数据，没有绑定 HTTP、日志、JSONL、业务数据库或固定文件输入格式。

| 场景 | 完整输入 | 公共API与下游处理 | 输出 | 独立读取断言 |
|---|---|---|---|---|
| 业务商品汇总 | `Array[Sale]`：教学套件 `<A>&B` 数量2金额50；耗材数量5金额12.5 | 下游自行求和；Cell Text/Number、Header/Decimal2/Highlight，Sheet set/merge/列宽，Workbook to_ods | `business.ods`，单表“业务汇总” | 标题跨度3及covered格、XML特殊字符原值、总数量7和金额62.5、金额样式Decimal2 |
| 科研/教学批次 | `Array[Sample]`：2024-02-29/-2.5/true/含中文空白备注；2026-10-01/0/false/空字符串；来源“合成批次 LAB-02” | Date/Number/Boolean/Text/Empty、DateISO，分表保留观测和元数据 | `laboratory.ods`，“测量”“记录来源”两表 | 日期、负数、零、true/false、中文双空格/tab/LF/emoji、空值与空字符串分别保留 |
| 已计算结果的公式声明 | 输入[1,2]；4组调用方表达式+缓存：SUM→99、比较→true、中文常量→文本、DATE→2026-10-01 | 下游传入 `Array[(String, Value)]`；Cell formula；不由库求值 | `declarations.ods`，“调用方缓存” | 4条公式文本逐字相等、number/bool/string/date缓存各相等；99故意与SUM矛盾，证明没有计算器 |

odfpy实际核对30个类型值；每份文件的content/styles/manifest均用官方ODF1.3 RNG校验，共9 XML；zipfile检查CRC、路径、mimetype位置与header。生成器和读取器分别运行，不导入MoonODS实现来解析。两个独立生成进程的三份文件SHA256相同。另有4项MoonBit下游测试覆盖不同输入、空清单/空观测、缓存保存、字节确定性。测试通过不证明任意业务都适合此MVP。

## 候选包消费证据的准确范围

`scripts/verify_reuse.py` 实际执行 `moon package --frozen --list`，复制候选ZIP、核对CRC/文件清单及源码SHA256。`.moonignore`排除开发证据、vendor归档、验证脚本和消费fixture，保留实现、许可证及文档。候选包与提交历史源码ZIP不同：前者用于模块消费，后者用于审阅和复现。

脚本在新临时目录解压候选包，复制独立消费模块，并建立只有这两个成员的 `moon.work`。消费模块编译依赖来自解压候选，没有链接回原工作目录；zipc/flate用当前已备索引及源码缓存解析，日志记录“Using cached”。此路径采用Moon官方支持的本地workspace依赖，版本字段在workspace中不负责远端选择。候选源码与当前实现字节对照、候选摘要、消费源码摘要、命令、退出码及生成文件的最新记录在 `evidence/date-width-release/reuse/`，早期复用阶段证据保留于 `evidence/2026-10-01-reuse/`。

**这是本地候选模块消费通过，不是从Mooncakes安装通过。** 此本地消费阶段没有发布、远端拉包、用户安装或全新机器初始化；同一已有SDK/Node/Python/schema/第三方缓存是复现前提。候选ZIP本身没有承诺跨次打包字节一致；确定性声明仅针对ODS输出。已获批准的首发及独立注册表验证单独记录于RELEASE_ZH，不能用本段历史本地验证替代。

## 公共API审查与生态定位

- Workbook负责表集合、输出预算和完整ODS字节；Sheet负责坐标、列宽、合并；Cell负责值、缓存及样式。返回错误可恢复，容器不透明，消费模块无法直接改内部Map/数组。
- 三个下游适配器分别拥有自己的输入类型与计算/来源处理，核心无特定领域字段。调用方持有Sheet引用，当前写出路径不需要新增表枚举/查找接口。较早复用复核未因提交数量修改API；后续边界阶段增加可选日期政策是实际互操作性处理，不改变默认ODF日期能力。
- 有界内存、五种样式、Double数值、纯年月日是实质范围限制。32表、1024行、128列等上限使其适合小型报告；不把它包装为任意规模/任意精度/全ODF表格工具。
- markitdown的ODS→Markdown属于读取转换；MoonODS消费业务的类型化数据生成ODS。XLSX读写生态存在交集，不能用writer标签或语言不同独自证明原创，也不能声称生态绝无同类。来源快照见SOURCES。
- RNG/odfpy通过属于文档结构和值层。现有 Excel 16.113.3 已实际打开四个自制 ODS，20 组常规核值通过、整体 PARTIAL；绝对毫米列宽与公元 0001 年兼容缺口尚在。LibreOffice、Numbers、WPS 未测；不能将 Excel 结果称为 LibreOffice 通过，也不把 Excel 导入时重算称为 MoonODS 求值。

目前补齐了可审阅的跨模块复用证据。是否有足够真实需求、是否适合十月项目、是否满足官方最终规则需用户与官方判断。当前十月表单已完整读取，明确至少 10 次有效提交；Git 按真实阶段保留记录，不拆空提交凑数。章程 5.1 原句“申报书务必人工撰写”，十月表单明确“不要使用 AI 编写”；本材料仅为 AI 辅助技术事实，用户应理解后自行撰写最终申报。

本轮独立消费模块的日期公式缓存显式从Cell::excel_1900_date(...).value()取得，验证候选导出新公共方法，数据与输出仍与旧场景相同；通用实验适配器仍支持默认ODF日期，没有强制绑定Excel。

最终重打包逐字节核对候选全部文件（含文档、许可和接口），保存all_files_sha256及all_candidate_bytes_match_checkout；消费的源码和说明来自同一当前快照。较早候选文档少一段提示的版本作为阶段证据保留，不以它证明最终说明一致。
