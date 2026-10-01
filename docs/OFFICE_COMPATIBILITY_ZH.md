# 已装桌面软件真实读取

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

LibreOffice、Numbers、WPS未实测。没有安装LibreOffice，也不把Excel/odfpy称为LibreOffice通过。

## 本轮规范判定与有界处理

ODF1.3 §19.374/§18.3.14将日期值关联XML Schema date/dateTime；官方RNG与独立odfpy接受0001-01-01。Microsoft[日期系统](https://support.microsoft.com/en-us/excel/date-systems-in-excel)及[限制](https://support.microsoft.com/en-us/excel/excel-specifications-and-limits)说明计算下界1900-01-01（1904系统为1904-01-01）。结合既有实读，判断极早日期是Excel支持范围差异，未发现MoonODS生成错误；不改变合法ODFDate的默认行为。

新增可选`Cell::excel_1900_date`提前拒绝1900以前/无效公历日，并选择DateISO。它不设置阅读器日期系统，不保证全部应用兼容。历史显示可显式用Text，类型和算术语义不同，不自动降级。回归覆盖0001/1899、1900/2000闰年/9999、年0/10000与虚构1900-02-29拒绝。

ODF §20.254/§18.3.26的column-width为固定positiveLength，毫米单位合法。回归核1/32/500mm与列引用逐项对应、替换值、非法-1/0/501拒绝后字节不变；独立RNG也拒绝负长度。API承诺源文件请求值，不承诺各阅读器物理布局。

Microsoft[VBA Range.Width](https://learn.microsoft.com/en-us/office/vba/api/excel.range.width)定义为point，但本次实测是Mac AppleScript/JXA，不是VBA；既有Excel16.113.3的sdef仅说明返回范围宽度，**未注明单位**。不能直接套VBA约定。数据近似96单位/英寸只是假设，不是校准；原point换算FAIL继续保留，绝对毫米UNRESOLVED，不改成PASS或向writer加入像素补偿。

本轮仅读规范/本机字典和执行非原生回归，未激活Office、System Events或截图，不占Pixel焦点。新的诊断例未原生实读。Library历史v2及旧真实报告保留；审查草稿结果在`evidence/date-width-final/`，最终重打包/消费结果在`evidence/date-width-release/`。统一技术复核后按真实阶段提交；较早spec-review记录中的待提交状态属于草稿阶段。

`excel_1900_date`只是日期范围政策，不是完整Excel兼容过滤器。Microsoft还列出公式8192字符、单元格253换行、列宽255字符等上限；MoonODS的ODF存储限制不同，没有声称这些合法ODF输入全能在Excel保留或计算。任意公式与500mm边界的原生读取仍未测，不把字典/规范检查称为实测。
