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
