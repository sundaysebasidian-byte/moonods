# 0.4.0 类型与基础格式契约

0.4.0 的类型和格式子集；相对已发布 0.3.1 的变更及迁移见[版本说明](release-0.4.0.zh-CN.md)。源码测试、Office 历史验证、远端 CI 和正式包消费分别记录，不承诺所有办公软件兼容。

## 类型契约

新增 Value 分支：`Percentage(Double)` 为比例原值（0.25即25%），`Currency(Double, String)` 保留金额和三位大写币种标识，`Duration(String)` 保留带符号日/时/分/秒时长字面值，`DateTime(String)` 保留公历日期、时间、可选1..9位小数秒及原始UTC偏移/无偏移形式。时间字符串的相等性按原字面值，不做时区转换、日历时长换算或通用时间运算。

默认读取行为保持原有限类型；需显式 `allow_extended_types=true`。这避免原调用者突然接受此前拒绝的货币/时长输入。新增 enum 分支会影响穷尽 match 的源码兼容性，升级到 0.4.0 时须更新穷尽匹配；0.3.1 不含新增分支。

金额仍基于 binary64，不提供十进制金融算术。货币输入若原始十进制与 binary64 再序列化值不同，直接拒绝，而不是改金额后继续；普通 Number/Percentage 的既有精度诊断仍适用。币种只验证三位大写形状，不声称查验当前所有ISO4217代码。时长不接受年/月；时间戳不接受闰秒、24:00或超过±14:00偏移。拒绝不会强转为普通Number/Date。

ODS 输出按真实类型写属性，并生成带类型的数字格式，防止仅写值类型却使办公软件按无格式float回存。类型格式覆盖基础样式的数字格式部分；背景、粗体等基础属性保留。CSV默认拒绝这些新值，需显式 `extended_types_as_text=true` 才输出可见的 `currency:USD:12.5`、`percentage:0.25`、`duration:PT1H30M`、`datetime:...` 字段；这是有标记的文字交换，不是CSV类型保真或自动金融数值导入。records保留完整Value分支。

## 基础格式契约

需显式 `preserve_basic_formatting=true`，仍须接受其余格式/元数据损失。读取styles.xml和content.xml中的实际定义，解析父样式及族默认值，按照单元格显式样式、行默认、列默认、族默认的顺序选择。仅完整匹配现有Plain/Header/Highlight/Decimal2/DateISO有效属性及数字格式定义时，归一为该预设；名字Header或W40本身不作为依据。未知属性、未解析/循环/过深继承、冲突定义不会被猜作已保真。

列宽使用整数有理数精确换算mm/cm/in/pt/pc，只保留1..500的整数毫米。非整数结果、像素DPI、比例/最优宽度或冲突定义报告损失，不四舍五入。`Cell.style()`和`Sheet.column_width(col)`可检查当前归一预设和显式毫米宽度。

导入定义数上限2048、继承深度16、样式解析缓存2049项；输出的类型数字格式与单元格格式合计最多1024项。只输出固定预设和类型格式，不复制任意来源XML。原ZIP、4MiB解压、XML、文本、网格和诊断上限不提高。字体/主题、行高、排版和复杂样式仍明确报告损失。默认样式新增属性可能使原本可识别的预设变成不可表示组合，此时明确丢弃并诊断，不把近似当保真。

## 当前证据

本轮 JS 全项目回归、Python 控制和真实 LibreOffice 25.2.3.2 headless 闭环已有通过回执，最终数量及源码哈希见交付回执。`verify_extended_compat.py` 用完全合成 FODS 经真实 LibreOffice 生成输入，再读入、保留币种修改金额、导出、独立比较、ODF schema 校验、LibreOffice 回存、再读。它没有把自身 writer 输出当作唯一外部输入。

精确十进制比较器默认不经过 Python float；正负零、大于2^53精度、权威字符串属性、表头/正文容器顺序及合并、币种/比例类型/时间偏移/时长符号的篡改控制会检测差异。`verify_basic_formatting.py` 独立比较有效样式属性和数字格式，并以值不变但颜色改变的负例检查样式比较器。typed 值相等不等于样式相等。

实测边界：5in 列宽对应127mm，经过 Office 闭环保留；Office 将4cm保存为1.5752in，换算40.01008mm，不在整数毫米子集内，导入明确丢弃。带偏移时间戳在库自身往返逐字保留，但 Office 将 `2026-10-26T01:30:00.125+08:00` 回存为无偏移的 `2026-10-25T17:30:00.125`，因此不宣称 Office 时间偏移保真，也不据此假定时区语义等价。Office 可将时长规范化为另一等价字面值；比较阶段明确使用实际生成的 ODS，而非声称原 FODS 字面完全不变。

另已隔离配置官方0.10.17 WASM编译器、其内置core、指定moon/moonrun及同版官方runtime来源；原SDK未覆盖。最小Wasm/WasmGC在debug和release仍失败，native的C/x86后端被该WASM snapshot明确禁用，不能冒称项目四后端通过。完整原生编译器发行物仍为环境缺项；不改安全配置或重试已拒绝CDN/API。

## 源码迁移

调用方穷尽匹配 `Value` 时需处理新增四个分支；不接受这些语义的转换器应明确拒绝，不能统一降成 Number。原读取调用默认仍拒绝扩展类型。启用时同时传 `allow_formatting_loss=true, allow_extended_types=true`；需保留已知基础格式时再传 `preserve_basic_formatting=true`。CSV 另需 `extended_types_as_text=true`，该策略与读取选项独立。本轮不修改版本号、tag 或注册表包。
