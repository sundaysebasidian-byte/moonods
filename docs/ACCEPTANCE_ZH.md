# MoonODS 中文验收矩阵

状态：2026-10-02 **本地0.2.0候选**。历史0.1.0已公开/发布；当前新源码未推送、未发布、未报名。本文件是AI辅助客观工程记录，不是最终人工申报书或官方终验结论。不保证一次验收或奖金额度。

## 终验九条

按已完整阅读的章程§5.1阶段三顺序整理；10/2尝试更新官方页面，飞书网页工具未能访问，因此规则仍依据10/1完整快照，不冒称已再次读取全部最新章程。

| 官方条目（事实摘要） | 当前候选状态 | 材料与缺口 |
|---|---|---|
| 1. MoonBit为主要实现语言 | 本地满足 | Cell/Sheet/Workbook/XML/ZIP核心为MoonBit；Node只保存示例Bytes，Python只验证 |
| 2. GitHub公开、提交清晰 | 历史0.1.0已公开；新改动仅本地 | 真实Git历史随源码包；本轮无push，新候选不在公开仓库中 |
| 3. 源码清晰并实现核心功能 | 本地验证通过 | 类型值、缓存、多表、5样式/列宽/合并、固定ODF包；新增整行原子写入和日期缓存默认样式 |
| 4. README目标、安装、用法、示例可复现 | 本地通过；用户理解待做 | 区分0.1.0注册表安装与0.2.0本地workspace；实际候选换目录消费，源码ZIP换目录复现另附记录 |
| 5. CI覆盖检查、构建、测试 | 工作流已具备，本候选远端NOT RUN | 本地fmt/check/build/test通过；远端旧25+4只证明0.1.0的旧SHA，不迁移为30+5通过 |
| 6. 至少一个可运行示例 | 本地通过 | 销售、实验多表、公式声明、edge及日期/单位例；独立消费三完整场景 |
| 7. 完整测试覆盖核心路径 | 有界范围通过；非穷尽 | 31核心/API、5独立消费、官方RNG/odfpy/ZIP/负控制；Excel与LibreOffice整体PARTIAL；规模/RSS/其他后端未测 |
| 8. 发布mooncakes.io | 0.1.0历史首发通过；0.2.0未发布 | 新代码与发布版不同，禁止拿旧注册表41文件/4测试报告冒充新版本发行 |
| 9. OSI许可及引用/移植合规 | 材料已核 | 原创MIT；core/zipc/flate Apache-2.0；原OASIS资料不重新授权MIT；fixture合成；AI来源如实声明 |

## 真实测试矩阵

| 检查 | 结果 | 当前证据/解释 |
|---|---|---|
| JS fmt/check/build `--deny-warn` | PASS | 精确moonc0.10.14/moon0.1.20260920，既有SDK；`-j 1`；Node/Python/独立验证依赖现已严格核锁 |
| 核心27 + 同模块公共API4 | 31 PASS / 0 FAIL | 保留旧25；新增最终32MiB封装（含头部）精确边界/超限、整行类型值/边界、后段合并冲突整批回滚、净替换预算、外部API列边界及日期公式默认样式 |
| 独立模块0.2.0候选消费 | 5 PASS / 0 FAIL | 真`moon package`、解压新目录；销售与实验真实用set_row；30类型值、9 XML；不从注册表安装0.2.0 |
| 官方ODF1.3 RNG | PASS | 固定摘要官方原schema，主4ODS/12XML；日期单位3XML；独立消费9XML；非法document/manifest控制拒绝 |
| ZIP、CRC及严格头部验证 | PASS | 路径/MIME/顺序/CRC；本地与中央头逐字段、EOCD/连续条目/尾部一致性；15个坏包控制被拒绝 |
| 原本地头CRC缺口 | 原FAIL，验证器已修复 | baseline/header-probe.json记录旧验证器错误接受本地CRC不一致的自制包；不是writer曾写错CRC |
| odfpy核值与XML语义 | PASS | 主例38类型值；独立30；诊断7；中文、转义、CR/tab/LF/emoji、Empty≠空字符串、长文、日期、四类公式缓存、样式/列宽/covered格 |
| 两独立进程确定性 | PASS | 主4文件、诊断1、消费3；相同数据/表序/SDK/JS后端字节相同，不承诺其他工具链或app回存相同 |
| 验收CLI运行环境漂移控制 | 按预期拒绝，控制PASS | 任务临时PATH中只模拟node版本v0.0.0；CLI退出1，在编译测试之前拒绝，无全局环境修改 |
| 新候选冒充旧注册表报告控制 | 按预期拒绝，控制PASS | 0.2.0候选SHA不匹配冻结0.1.0moon.mod；退出1且未调用registry-update，不联网 |
| 既有LibreOfficeDev实际导入/ODS原生回存 | 33值 + 2合并 PASS；整体PARTIAL | 26.8.0.0.alpha0；8固定无宏输入，临时profile；原文件SHA不变；独立odfpy读应用回存 |
| LibreOffice首次XLSX试验 | FAIL保留 | 布尔公式在XLSX导出表现为数值1；原生ODS保持Boolean；不宣称XLSX转换无类型变化 |
| LibreOffice原生DATE缓存探测 | 原缺口已修 | Plain缓存回存float46296；日期公式默认DateISO后保持Date及2026-10-01；显式改样式仍由调用方负责 |
| Excel16.113.3历史桌面读取 | 常规20组PASS；整体PARTIAL | 本轮没重开Excel；当前主4ODS哈希与旧输入完全一致；不因此声称set_row所有新输入均测过 |
| Excel旧32768字样本 | 原FAIL，已修并真实重读 | 原截至32767；库限制32767 UTF-16，旧失败保留；当前LO原生回存也核32767完整 |
| Excel极早日期 | 兼容缺口保留 | 0001年#N/A/API无值；ODF有效日期1..9999仍支持，未偷偷改类型 |
| 绝对毫米列宽 | UNRESOLVED | XML请求值/比例通过；旧point假设FAIL保留；GUI/打印物理毫米没有校准 |
| LibreOffice稳定版/GUI/打印 | NOT TESTED | 已测开发版headless，不等于所有LibreOffice版本或桌面版全通过 |
| Numbers/WPS/其他后端/性能及RSS | NOT TESTED | 不虚构实测；数据和字节预算不是峰值内存或速度证明 |

完整命令、实际退出码和stdout/stderr：`evidence/overnight-2026-10-02/final-budget/acceptance.json`；应用证据：`evidence/overnight-2026-10-02/libreoffice-final/libreoffice.json`。较早baseline、implementation、date-fix、LibreOffice-first和ods-probe均为有时间及源码快照的阶段记录；不把重复运行累计成独立测试数。源码ZIP换目录复现随交付提供，复用可信SDK/core、依赖缓存、现有Python/schema，不称全新机器或完全离线无缓存初始化。

## 人工规则与待办

已读取章程11章/附录、十月表单16字段与诚信承诺。章程第五章5.1原句“申报书务必人工撰写”，表单“不要使用 AI 编写”。技术参考不能直接提交或机械改写冒充人工；用户需理解后自行写一页内Markdown，至少3完整场景、至少10有效提交的认可由官方判断。真实历史保留，不空提交、补造日期或机械拆分凑数。本轮无最终申报/代签/同意动作。

章程10/24与官网10/31旧快照冲突保留；内部10/24前准备，最终适用时刻未确认。章程原则上一项目、表单三次提交与用户核群公告每人单月最多三项目分别保留。150+350均有审核条件，不保证自动到账或1500净收入。个人身份/电话/银行/学籍/诚信由用户处理。

本轮不改已提交ABNF、MoonSTOMP或九月LogLens；不push/publish/submit。源码ZIP和Library更新属于本地交付，不能称官方验收通过。AI辅助事实、依赖来源与许可见AI_USAGE、SOURCES及THIRD_PARTY_NOTICES。
