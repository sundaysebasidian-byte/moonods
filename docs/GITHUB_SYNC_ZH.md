# MoonODS 2026-10-04 GitHub源码同步

原公开仓库：[sundaysebasidian-byte/moonods](https://github.com/sundaysebasidian-byte/moonods)，分支`main`。本次同步0.2.0候选源码、README、独立消费测试和真实应用证据；不重写历史、不force push。Mooncakes仍为已发布的`0.1.0`，本次没有发布0.2.0包。

此前远端`19e8ca30e481b9a1a685073f3f09dfa472bc72e6`与本地`b39d17b84450b1d1a423722d7960a84ead1c01e1`为祖先关系，核对时远端没有新增提交。本轮核心实现取自已验证的b39d17b：整行原子写入、日期公式缓存DateISO默认、Header三文字字重、严格ZIP一致性与有界资源策略。保留实际阶段提交，不以数量代替质量。

本地完整验收见`evidence/github-sync-2026-10-04/local/acceptance.json`：31核心/API与5独立消费测试；真实`moon package`候选解压到另一模块，逐文件核对、check/build/test/run和三个完整场景的30类型值/9官方RNG XML。主示例38类型值/12 XML、日期单位例7类型值/3 XML、跨进程字节一致及负控制分别记录。

真实已装LibreOfficeDev26.8.0.0.alpha0的证据在`evidence/overnight-2026-10-03/libreoffice-formatting/libreoffice.json`：8文件、33类型值、2合并、50保存格式属性PASS；7项检验器内存负控制PASS。当前源码与已测ODS输入摘要对应，本次文档同步没有改变核心输出。整体Office兼容仍PARTIAL；当前Excel、稳定LibreOffice、GUI/打印、绝对纸面毫米、Numbers/WPS未测，不将CI或odfpy称为Office实测。

远端CI由`.github/workflows/ci.yml`对每个同步提交执行锁定SDK/Node/Python的check/build/test、独立RNG/包检查及解包消费。具体提交的运行与终态查看[MoonODS checks](https://github.com/sundaysebasidian-byte/moonods/actions/workflows/ci.yml)；该工作流不运行Office应用。旧19e8ca3的25+4成功只证明旧提交，不能引用为新0.2.0通过。

公开内容保留MIT、第三方许可、AI使用及验证边界。原始外部研究副本、个人表单响应、凭据、Library身份元数据和内部审批材料不纳入仓库。旧已公开的个人项目经历从当前文档删除，既有历史不重写。活动最终人工Markdown、个人材料、诚信声明与申请不由本次源码同步代办。
