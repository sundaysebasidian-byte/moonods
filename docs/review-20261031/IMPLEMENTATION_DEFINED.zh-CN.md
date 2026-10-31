# MoonODS implementation-defined 范围审计

公开技术说明，AI 辅助编制；验证范围见下文。审计日期：2026-10-31。公开基线：`897c906607e1ec5072e514599e846bdbe6defe3e`，树 `ff36f8b595e36dd45f85bd480fe41c28b63dc441`。

## 结论

本次把此前仅列举几个例子的说明扩展为**官方正文关键词清单、逐项分类、当前输出/接口行为和证据绑定**。对当前固定 writer 范围，已说明找到的相关选择；没有发现因此必须新增算法或把所有办公功能实现的依据。未因此宣称全文符合性：关键词盘点不能替代全部规范条款审查，外部显示/求值仍不受本库控制。

## 方法与证据

1. 下载 OASIS ODF 1.3 OS Part 1、2、3、4 原始 HTML，逐段提取 `implementation-defined`（也查空格变体）。按(part, section, text)保留不同条款位置，得到123个命中：Part1 1、Part2 11、Part3 41、Part4 70，包含定义、规范义务、重复主题与目录，不是123个独立功能要求。清单逐项保留 section；另查 implementation-dependent/specific，防止把不同概念混为一谈。
2. 标准区分：implementation-defined 需要说明；implementation-dependent 不具有同样的必需说明含义。产品安全预算和“未支持功能”不能假充标准指定的实现定义项。
3. 对与公开基线同树的最终冻结目录 的169份文件重新计算摘要，全部与既有最终源码清单一致；这与公开树的对应由此前公开回执证明。
4. 本次独立重读10份最终 DTD 正例保存输出，均为4部件、CRC正确、XML可解析，枚举实际元素/属性。**这是重新检查保存产物，不是本次又执行10次CLI，也不证明所有输出组合。** 原运行的独立RNG/语义检查属于历史验收，本附件只承诺可复核其保存输出的结构。
5. 独立规范审查发现早期仅按文本去重会遗漏不同条款的相同文字（如Part2 §4.16.3、Part3 §19.164及Part4多个函数）；已改为逐条款去重并补扫Part1。首次输出扫描误包含负例哨兵，修正为仅选择原回执 positive 样本；首次源码定位是早期目录，发现README/CLI注释两处摘要不同，转至精确冻结目录重新验证。没有覆盖原测试基线。

## 当前行为声明及标准映射

| 范围 | 当前行为与审计结论 | 证据 |
|---|---|---|
| 包层自定义算法/IRI：Part2 §4.16.1、4.16.3、4.16.6、4.16.9、4.17；§2.2.1(E) | writer不生成加密、PGP或自定义算法IRI；reader拒绝加密内容/密钥。不是“实现了一套加密默认算法”。 | package.mbt:5–11、76–90；reader_manifest.mbt:26–27、64–65 |
| 默认/偏好视图：Part2 §4.16.11 | writer不写preferred-view-mode；库没有GUI/默认打开视图，reader不据此选择视图，也不保留视图设置；数据导入总损失诊断明确告知view settings不保留。应用打开后的视图由应用决定。 | package.mbt:5–11；reader_manifest.mbt；reader.mbt 中 DATA_ONLY_IMPORT |
| 公式HOST-LOCALE：Part3 §19.646及Part4计算器条款 | 本库不托管通用公式求值器，因此不选择公式计算locale、1900闰年兼容、比较转换或函数变体。公式文本+缓存保存，完整OpenFormula语法不验证；外部引用文本不会由库联网解析。固定采购模板例程不是通用公式引擎。 | cell.mbt:55–76；xml.mbt:101–102；examples/reconcile/main.mbt |
| 无换行时的溢出：Part3 §20.230 | Plain/Header/Highlight显式wrap；Decimal2/DateISO及扩展格式没有全部显式wrap，因此**不把该条笼统列“不适用”**。库不渲染、不选择超出单元格文本可见/隐藏策略；由消费者处理，不保证视觉一致。 | style.mbt:28–29；typed_format.mbt:16–30 |
| 缺省样式/地区显示：Part3 §16.2（implementation-dependent）及数字格式 | 未输出language/country/calendar。N2固定两位小数，DISO固定年月日组成与连字符，百分比/货币/时间有固定格式构件；最终地区分隔符、日历/字体/默认样式效果不做跨应用保证。不得将implementation-dependent错写为本库遗漏的“所有必需实现定义值”。 | style.mbt、typed_format.mbt；style_wbtest/layout_wbtest |
| 自定义元数据、光标PI、签名与索引标记：Part3 §3.11、3.16、4.3.1、8.8.3 | 固定writer不生成这些元素/部件/PI，因而不定义其自定义语义。导入是数据型转换，不能宣称完整保留。 | package.mbt 固定四部件；workbook.mbt:168–264 |
| 图表/绘图：Part3 §11.3、11.5、19.155、19.164、20.61、20.176–179 | writer无chart/draw内容，没有图表轴、光照、符号或对象可见区域自定义选择。 | writer词汇审计及保存输出词汇清单 |
| 表单/数据库/演示：Part3 §13.5.25、19.85.4、19.264–265、19.418–421、20.238 | writer不输出对应结构，未提供数据源映射、控件或动画速度语义。 | 同上 |
| 事件、批注/索引/保护/透视：Part3 §14.5.3、16.31.3、19.677.11、19.702、19.714、19.857 | 对应事件/脚注配置/侦测高亮/保护算法/数据透视缺省行为不由writer产生。本项不表示所有导入结构会被接受或保留。 | 同上 |
| 其他视觉样式：Part3 §19.493、19.497、20.315、20.377、20.383、20.392、20.395 | writer不设置这些引导线/脚注分隔/严格断行/装饰线宽/窗口颜色属性；若消费端通过缺省样式产生显示选择，不受本库控制。 | style.mbt、typed_format.mbt |

## 公式边界补充

Part4全部70个关键词命中中，目录/术语/建议项不当成功能要求；其余涉及公式求值器、转换、函数、引用解析与数值处理。当前通用库不求值，因此不能声称这些行为已经测试，也无需为了“仅存储公式”选择每个函数的未定义分支。`of:=`前缀检查不等于完整公式语法验证，缓存不是重新计算结果。

采购例程只接受固定表契约和已知算术公式，并用有界整数分/数量计算；其业务规则是示例契约，不是OpenFormula兼容声明。将来若加入通用求值，必须重新审计Part4，不能沿用“未托管计算器”的结论。

## 实现选择（不是冒充标准implementation-defined）

- ZIP固定路径、STORED、固定时间字段；确定性输出。四个部件：mimetype、content.xml、styles.xml、META-INF/manifest.xml。
- 有限binary64；不接受非有限值，不保证十进制金融精确计算；日期范围1..9999；货币代码只验证三个大写字母，不验证ISO4217成员资格。
- 精确物理长度mm/cm/in/pt/pc、≤500mm、最多12位十进制数字；旧整数列宽与精确列宽不同接口，不推断缺省optimal值。
- 支持的字符串值与显示文字可不同；图像、签名、全部样式和视图不保真。必须显式接受损失，不把确认损失当作忽略错误许可。

## 可复核性与剩余边界

本目录提供 `audit_implementation_profile.py`、`IMPLEMENTATION_PROFILE_RECEIPT.json`、逐条分类CSV及标准源摘要，附10份合成保存输出与源码摘要清单；取得公开固定提交源码后可在已有lxml环境只读复核，完整四后端运行及原始输入夹具并未全部附入；不依赖新增安装，不改源码。原来的4后端202/202与23步是既有功能阶段证据，未在本轮重跑。

**已补上：** 当前producer范围内的实现定义项说明与全量关键词归类，而不是继续笼统写“尚未审计”。

**尚不能称为完成：** 全标准符合性认证、全部潜在默认渲染行为实测、完整OpenFormula验证、最新版本Office GUI全矩阵互通。

官方来源：[Part2](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html)、[Part3](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)、[Part4](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part4-formula/OpenDocument-v1.3-os-part4-formula.html)。
