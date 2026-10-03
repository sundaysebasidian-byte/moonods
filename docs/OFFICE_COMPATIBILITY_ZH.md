# 已装桌面软件真实读取

## 2026-10-03：当前样式修复及格式验证

Header补齐亚洲/复杂文字字重后，当前ODS字节已改变；旧Excel输入哈希不再匹配，旧实测保留为历史，不声称当前Excel已测。实际重新调用已装LibreOfficeDev核8新文件：33值、2合并及50保存格式属性PASS，7检验器负控制PASS；其中18列宽保存长度在声明0.02mm容差内符合请求。整体PARTIAL；GUI字形、稳定版、纸面毫米与Excel单位校准未测。[本轮详情](FORMAT_VERIFICATION_ZH.md)。

## 2026-10-02：既有LibreOfficeDev的真实无界面读取

发现Codex文档运行环境已经附带`LibreOfficeDev 26.8.0.0.alpha0 2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`。本轮没有下载或安装LibreOffice。通过指定该工具的完整路径、一次性UserInstallation目录、无界面Calc导入8份固定无宏合成ODS，原生回存到另一目录，再用odfpy核对33类型值与2合并；全部通过，输入SHA256未变。脚本退出后临时profile删除，没有服务监听或持久访问。详细命令、stdout/stderr、原生回存文件及输入摘要见`evidence/overnight-2026-10-02/libreoffice-final/libreoffice.json`。

整体兼容状态仍为**PARTIAL**：测试的是已带开发版和无界面导入/保存，未进行稳定版、GUI显示、打印或绝对毫米列宽校准。Numbers/WPS仍未测。应用回存可能采用其自身ODF版本，不能把回存文件声称为MoonODS生成的确定性ODF1.3包。

首次XLSX导出检验把布尔公式的数值输出1与预期Boolean比较，FAIL保留在`libreoffice-first`；这表明XLSX转换会改变结果表示，不能用来声称ODS布尔缓存丢失。随后原生ODS探测保留Boolean，却把Plain样式的DATE公式缓存变为float46296。0.2.0修复`Cell::formula(Date(...))`的默认样式为DateISO；复测原生ODS回存保持日期类型及日期值。仍可显式覆盖样式，且库不会求值或修正缓存。

故意不一致的SUM缓存99在原生ODS回存仍为99；首次XLSX导出重算为3。两种真实应用路径都有记录，不能承诺所有办公软件或导出方式都保留原缓存。33断言也核查中文、CR/tab/LF、emoji、32767字长文、极大/极小有限数、两表、布尔及公式四类缓存。

本轮未重开Excel；四份原Excel输入与当前生成字节相同，旧20组结果仍可作为这些固定文件的历史证据，不证明新整行API或所有新输入都已在Excel验证。以下保留原始2026-10-01桌面实测记录。

2026-10-01使用既有Microsoft Excel16.113.3打开四个任务自制无宏ODS，仅读取，未保存。虽传入只读参数，Excel实际报告readOnly=false，不能声称强制只读；逐文件SHA证明输入未改变。系统osascript、执行脚本、stdout/stderr保留，无新增安装。

## 通过范围

`evidence/office-2026-10-01-fixed/excel.json`：常规20组断言PASS，整体PARTIAL。

- 销售：中文/XML特殊字符、销量20/金额399.88、2026-10-01、Header背景RGB[23,50,77]/粗体、两位小数、A1:D1合并正确。
- 实验：样本/元数据两表，2024-02-29、-0.125、true/false、零、中文双空格/tab/LF/emoji、12000字备注正确。截图Decimal2显示-0.13，底层读取-0.125，显示精度不等于值截断。
- 公式：Excel导入公式，读取30/true/中文结果/日期；可能重算，不是MoonODS计算能力。源缓存由独立odfpy/XML核对；故意矛盾缓存99见独立消费场景，未用Excel证明不会重算。
- 长文：旧32768字样本截至32767，修正实现上限为32767 UTF-16单元，超限先报错；新32767样本完整读取。总预算与替换记账仍精确覆盖。

## 限制和失败

0001年日期显示#N/A/API无值。ODF合法公历1..9999保留，不保证Excel全范围。9999年底序列值可读，Plain显示12/31/99，完整年月日可选DateISO。

列宽API返回[121,242,91,128]，声明毫米[32,64,24,34]。按point假设换算检查FAIL，失败保留；比例PASS。源XML毫米属性正确，绝对物理毫米未独立校准，不能标通过或据此判writer错误。

Excel value2把Empty与Text("")均呈现空字符串，源区别由独立读取/XML确认，不能声称API保留区别。窗口Calculation Settings提示正则表达式公式可能有不同结果；未测这类公式，不宣称所有函数兼容。

`evidence/office-2026-10-01/`为修正前，保留访问/打开失败、单位假设和长文截断。销售/formulas截图视觉核对过；早期错名实验截图改为`duplicate-sales-window.png`，不能当实验截图。正确实验截图为`office-2026-10-01-fixed/experiment-window.png`，通过指定Excel窗口编号截取、视觉核对。截图辅助核值，以真实API日志为主。

截至10/1该阶段，LibreOffice、Numbers、WPS尚未实测；10/2、10/3另有已装LibreOfficeDev真实无界面记录，Numbers/WPS仍未测。全程没有新安装LibreOffice，不把Excel/odfpy称为LibreOffice通过。

## 本轮规范判定与有界处理

ODF1.3 §19.374/§18.3.14将日期值关联XML Schema date/dateTime；官方RNG与独立odfpy接受0001-01-01。Microsoft[日期系统](https://support.microsoft.com/en-us/excel/date-systems-in-excel)及[限制](https://support.microsoft.com/en-us/excel/excel-specifications-and-limits)说明计算下界1900-01-01（1904系统为1904-01-01）。结合既有实读，判断极早日期是Excel支持范围差异，未发现MoonODS生成错误；不改变合法ODFDate的默认行为。

新增可选`Cell::excel_1900_date`提前拒绝1900以前/无效公历日，并选择DateISO。它不设置阅读器日期系统，不保证全部应用兼容。历史显示可显式用Text，类型和算术语义不同，不自动降级。回归覆盖0001/1899、1900/2000闰年/9999、年0/10000与虚构1900-02-29拒绝。

ODF §20.254/§18.3.26的column-width为固定positiveLength，毫米单位合法。回归核1/32/500mm与列引用逐项对应、替换值、非法-1/0/501拒绝后字节不变；独立RNG也拒绝负长度。API承诺源文件请求值，不承诺各阅读器物理布局。

Microsoft[VBA Range.Width](https://learn.microsoft.com/en-us/office/vba/api/excel.range.width)定义为point，但本次实测是Mac AppleScript/JXA，不是VBA；既有Excel16.113.3的sdef仅说明返回范围宽度，**未注明单位**。不能直接套VBA约定。数据近似96单位/英寸只是假设，不是校准；原point换算FAIL继续保留，绝对毫米UNRESOLVED，不改成PASS或向writer加入像素补偿。

10/1日期单位复核阶段仅读规范/本机字典和执行非原生回归，未激活Office、System Events或截图，不占Pixel焦点。新的诊断例未原生实读。Library历史v2及旧真实报告保留；审查草稿结果在`evidence/date-width-final/`，最终重打包/消费结果在`evidence/date-width-release/`。统一技术复核后按真实阶段提交；较早spec-review记录中的待提交状态属于草稿阶段。

`excel_1900_date`只是日期范围政策，不是完整Excel兼容过滤器。Microsoft还列出公式8192字符、单元格253换行、列宽255字符等上限；MoonODS的ODF存储限制不同，没有声称这些合法ODF输入全能在Excel保留或计算。任意公式仍未测；500mm保存属性在10/3 Calc中实测，屏幕/打印物理宽度仍未测，不把字典/规范检查称为实测。
