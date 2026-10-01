# MoonODS 中文验收矩阵

状态日期2026-10-01，按实际完整阅读的[章程§5.1](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)阶段三原顺序整理。本地交付状态不是官方终验通过，不保证一次验收或奖金额度。

## 终验九条

| 官方条目（事实摘要） | 当前状态 | 材料与缺口 |
|---|---|---|
| 1. MoonBit为主要实现语言 | **本地满足** | Cell/Sheet/Workbook/XML/ZIP核心为MoonBit；Node仅示例文件适配器，Python仅独立验证 |
| 2. GitHub公开、提交清晰 | **已公开** | https://github.com/sundaysebasidian-byte/moonods；完整真实历史；发行SHA/CI见RELEASE_ZH |
| 3. 源码清晰并实现核心功能 | **本地验证通过** | 类型API、公式缓存、多表、基础样式/列宽/合并、固定ODF包；范围与预算明确 |
| 4. README目标、安装、用法、示例可复现 | **本地完成；用户理解待做** | 工具链/依赖锁、真实日志、本地候选及真实注册表消费均通过，细节见RELEASE_ZH |
| 5. CI覆盖检查、构建、测试 | **远端PASS** | 首发源码6dced9e真实Linux CI含fmt/check/build/test/独立读取；最终交付提交结果见发行记录 |
| 6. 至少一个可运行示例 | **本地通过** | 销售/实验多表/公式声明三场景及edge实际运行，4 ODS附包；另有独立消费3场景 |
| 7. 完整测试覆盖核心路径 | **当前有界范围通过；非穷尽** | 25核心/API、4独立消费、RNG/odfpy/ZIP负控制；Excel常规通过、整体PARTIAL；不是任意ODF/规模/办公软件全测 |
| 8. 发布mooncakes.io | **已发布0.1.0；注册表消费PASS** | 空缓存实下载、41文件同候选、4测试/30类型值/9XML通过 |
| 9. OSI许可及引用/移植合规 | **材料已核** | 原创MIT；core/zipc/flate Apache-2.0原许可与引用、归档摘要；合成fixture；OASIS资料不重新授权MIT |

## 真实测试矩阵

| 检查 | 状态 | 证据范围 |
|---|---|---|
| JS fmt/check/build `--deny-warn` | **PASS** | 锁定moonc0.10.14与moon0.1.20260920，既有MacSDK，`-j 1` |
| 核心22 + 同模块公共API3 | **25 PASS / 0 FAIL** | 中文/XML转义/非法字符、非法/重复表名、非有限数、无效日期、空值/空字符串、长文、合并冲突/越界/数据损失、列宽、事务性错误与各资源预算 |
| 独立模块本地候选消费 | **4 PASS / 0 FAIL** | 不同模块从真实候选ZIP解压消费；3场景、30类型值、9 XML；不是Mooncakes安装 |
| 不透明API编译负控制 | **按预期拒绝** | `w.sheets.clear()`报Error4028；opaque-probe证据，不是正常运行失败 |
| 官方ODF1.3 RNG | **PASS** | 固定摘要官方原schema；4 ODS共12 XML；document/manifest无效控制被拒绝 |
| Python zipfile及负控制 | **PASS** | CRC、固定4路径、mimetype首项/STORED/no-extra/ASCII、headers/时间戳；路径/顺序/MIME/CRC破坏被拒绝 |
| 独立odfpy | **PASS** | 38类型值，中文空白/长文/多表/公式四类缓存；不导入MoonODS解析 |
| 新增日期/单位回归例 | **PASS（ODF层；Office未测）** | 7类型值、3官方XML，年0/负列宽负控制；1/32/500mm映射与显式Date/Text |
| 样式/列宽/合并XML语义 | **PASS** | Header/Decimal2、毫米属性、covered格；不等同于绝对视觉几何 |
| 两个独立生成进程 | **PASS** | 同SDK相同输入四ODS字节一致，不承诺任意SDK/后端一致 |
| Excel16.113.3真实打开/核值 | **常规20组PASS；整体PARTIAL** | 四自制文件，真实API/截图；值/样式/合并/公式导入；未保存，SHA不变 |
| Excel旧32768字边界 | **FAIL：截至32767，已修实现** | 修正前失败保留；上限收紧32767，精确总预算边界不降标准；修正后32767完整 |
| Excel极早日期 | **兼容缺口未解决** | 0001-01-01显示#N/A/API无值；ODF合法1..9999保留，不保证Excel全范围 |
| Excel绝对毫米列宽 | **UNRESOLVED** | 返回单位假设point的检查FAIL保留；比例PASS，绝对物理单位待校准，不标通过 |
| LibreOffice实际打开/核值 | **NOT TESTED** | 无已装工具且安装未授权；其他读取器不替代此项 |
| Numbers / WPS | **NOT TESTED** | 存在已装应用不等于实测 |
| 其他后端、性能/RSS | **NOT TESTED** | JS Mac/Linux已核；数据/输出预算不是进程峰值内存证明 |

最新串行结果：`evidence/date-width-release/acceptance.json`及stdout/stderr。Excel单独记录：`evidence/office-2026-10-01-fixed/excel.json`，详见[桌面兼容实测](OFFICE_COMPATIBILITY_ZH.md)。旧失败阶段保留：首次test-only导入、reuse-first/reuse-second、Office访问/打开失败、错误单位假设；不能用旧报告证明当前源码。

先前源码ZIP换目录检查在`evidence/source-package-check.json`，只证明较早快照。本轮源码ZIP独立换目录检查随交付另提供；均使用同一既有工具/schema/第三方缓存，不称全新机器或无缓存初始化。

## 申报规则和待办（不是终验第九条）

完整读取章程11章/附录、十月表单16字段及诚信承诺。十月表单明确至少3完整场景、至少10有效提交；按真实阶段提交，不凑次数。章程“申报书务必人工撰写”，表单“不要使用 AI 编写”。AI参考不是最终申报书，用户需理解并自行撰写一页内Markdown；个人身份/电话/邮箱/银行/学籍/诚信由用户处理，未代填/签署。

章程十月截至10/24，官网10/31；内部按10/24前准备，最终截止待官方明确。章程原则上一项目、表单三次提交、用户已核群公告每人单月三项目保留各自来源。150启动/350完成均有审核条件，不保证1500净到手。详见[规则复核](RULES_REVIEW_ZH.md)。

公开仓库及Mooncakes0.1.0首发已完成，实际CI和注册表验证见RELEASE_ZH；报名由用户处理；正式申报前复核同类与生态价值。当前检索不能证明唯一，九月LogLens不改成新项目。用户理解/审核未完成，不承诺一次过。

本轮新增可选Excel1900日期构造、历史日期/毫米回归与诊断例。默认ODF日期1..9999保留，不伪造Excel支持；Mac JXA单位无明确说明，VBA point约定不能直接套用。本轮25项测试与Library历史v2的22项快照区分；统一技术复核完成，按真实阶段提交，旧证据与失败记录保留。本次最终候选包括全部文档的逐文件SHA256匹配证据，避免已消费候选与最终说明滞后。

真实注册表消费另见 `evidence/publication/registry/registry.json`，不是moon.work本地候选消费；空索引/包缓存启动，既有SDK/core、Python及官方schema复用，不称全新机器。首轮CI失败、frozen发布预检失败保留，修复后远端25+4和注册表4均通过。
