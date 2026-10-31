# 源码修订技术证据

本分支基于 `6dcb77df291acf8b592224c7ba94ce648f395cc2`。当前运行锁见 [TOOLCHAIN.lock](../TOOLCHAIN.lock)，测试与API边界见 [README](../README.md) 和 [XML处理器说明](XML_PROCESSOR_API.md)。

## 前一处理器阶段的实际验证

- 包层冻结源码四后端根库+consumer各176/176；独立包层31份API夹具、58次CLI、13份编辑再导出检查；175阶段独立全包native542/542不与当前根库+consumer口径混算。
- GUI互通绑定170阶段JS SHA `178c84afc27716e2187a8b69cdce50185860a3d10cd6a850d2e65c234621821c`。合成输入经官方Calc26.8.2.2修改、另存、库读写再开；4与12、公式A1*3、合并A2:B2、布尔日期及中文均核验。
- Calc另存ODF1.4未套1.3 schema；库输出1.3通过固定OASIS RNG。输出 SHA `4fb13f713c5e354057dce2c0a2e467c3e960260d2170ffe3f151bcd7091f615c`。17条损失诊断需显式接受。
- 后续175阶段读取同一Calc文件另有回执；不能将170 GUI当成后续源码完整GUI验证。

原始运行日志、截图及独立审查回执在交付私有材料包，不在公开仓库，不提供失效私有路径链接。有限测试不是标准认证；不声明无损办公往返、通用公式执行、嵌入对象XML验证或签名验证。

[历史0.4.0技术索引](development-history/TECHNICAL_EVIDENCE-before-review-20261030.md)中的发布与CI仅适用于当时提交。当前分支远端CI是否通过必须核对实际commit回执。

前一集成176阶段严格串行验收23步骤全部通过；JS/WasmGC根库+consumer各176，隔离源码包消费者和固定mbtexcel联用均通过，记录的源码SHA与结束时实际文件逐一一致。其他两后端176由修复阶段实测；不声称远端CI运行。

## 历史182布局增量

精确物理列宽及固定行高：四后端各182/182；31份独立包+3份重复/尾行新包、Fraction及ODF1.3 RNG核验；JS/native独立consumer各9。182阶段集成严格串行23步骤通过，mbtexcel联用/冷消费者均通过。

## 新布局182阶段的实际GUI互通

官方LibreOffice26.8.2.2实际打开本阶段导出、另存、关闭再开，最后182再次读取Calc另存件并导出，再由GUI打开。A1修改7→8保持；原生另存XML列宽0.889in、固定行高0.2173in、optimal=false保持，独立Fraction尺寸差为0。界面以0.01in显示为0.89/0.22，不能把界面舍入读数当作底层XML精确值。对话框均取消未确认改变尺寸。该正控不证明所有视觉样式保真，仍有12条其他损失诊断。

本次GUI精确绑定182 CLI SHA `a60cad4b05d895b2df43e1b27c22b5b5050f7fd122c0a6cc0f7d7bc7039eef62`，并核对161份源码清单零差异；这与此前170阶段公式/合并GUI是两个独立回执。182阶段集成23步骤验收通过，源码hash结束逐项无差异；本段不是当前远端CI结果。

## 189规范反例修复

995e088的+1mm导出和段落原始空白曾实证失败，已在独立新副本修复并保留原失败。四后端各189/189、14段落两次CLI、18份writer输出RNG与独立consumer10项通过；Python oracle同步纠正原先依赖错误raw/CR显示语义的断言，原失败与负控保留。数据接口不是视觉保真承诺，旧182布局GUI不能证明189 CR路径GUI效果。

## 194 typed词法与CI引导修复

Typed值按XML S进行XSD/RNG collapse，数字、boolean token、正整数重复/跨度与text:s非负整数分别按各自词法处理，日期组件保持严格，字符串属性不被trim。四后端根库及consumer各194/194；独立74项实际ODS输入/输出RNG及值、计数、合并验证通过。此阶段没有新GUI回执。

公开7b10c16的三个工作流曾在SDK core bundle阶段失败，因项目内SDK向上继承父moon.work并寻找尚未恢复的flate；业务测试被跳过，不将它说成业务测试失败或通过。修复为新提取core建立独立workspace边界，保留完整SDK校验与bundle。旧失败exit255及新同路径bundle成功、锁定缓存归档完整安装472任务成功、7项安装器负控保留。CI的重复预check移至原有acceptance检查位置，避免生成依赖mbti之后才校验原锁；并未删除验收中的check。后续公开CI结论必须核对新head实际运行。
