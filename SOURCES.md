# 来源与查证记录

记录日期：2026-09-30～2026-10-01 UTC。仅说明实际读到的内容，不推断官方批准或绝对生态唯一性。

## ODF 1.3（实际下载原文和 RNG）

- [OASIS Packages](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html)：§2.2 package conformance、§3.2 manifest 对应、§3.3 mimetype 第一项/STORED/no-extra、§4.16.4 full-path。无实现定义扩展 IRI、加密、签名或 assets 入口。
- [OASIS XML Schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)：§9.1.2–9.1.6 table/row/cell/covered-cell/column，§6.1 whitespace，§19.371/374/383/388/389 类型属性，§19.646 公式命名空间。
- [document RNG](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-schema.rng)：实际阅读 table-table、table-table-cell-attlist/extra/content、covered-table-cell、table-column、table-row、style properties 相关定义；SHA256 `40bad03efdbb02825230d357da0aa6ac679934c5bf56c6281752c0c24d58e4e6`。
- [manifest RNG](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/schemas/OpenDocument-v1.3-manifest-schema.rng)：完整文件实际读取、严格 version=1.3、file-entry/full-path/media-type；SHA256 `8aee71f03484be112af972d622cc9031280c007b0a454ae8815e8e333c9bdd17`。

规范未在产品实现中整段复制。RNG 为 OASIS Open 2021 版权所有原始资料，由 fetch_schemas 下载并保持原版权头；未作为 MIT 源码在包内重新授权。fixture 为本项目合成业务数据，未复制规范示例、真实报表或他人表格。

## 复用组件

- MoonBit core：当前可信 SDK 0.10.14 附带的 Buffer/StringBuilder/UTF-8/collections；Apache-2.0。源码许可原件在 licenses。
- [moonbit-community/zipc](https://github.com/moonbit-community/zipc) 0.2.2：Apache-2.0。实际读 zip.mbt CRC API及 Archive 路径排序；复用 File::stored_from_bytes().decompressed_crc32()。归档 SHA256 `e552ecca64446aa9be8ced2dfae21f413e77ced2d21dfd0934772f32f30c43de`。
- [moonbit-community/flate](https://github.com/moonbit-community/flate) 0.2.0：Apache-2.0，为 zipc 传递依赖；归档 SHA256 `935372d9a49a5d4bbb40a2fd057bd36b587f683d605c5de204adc143a2215e66`。
- 测试使用现有 odfpy 1.4.1、lxml 6.0.2、defusedxml 0.7.1；不纳入 MoonBit运行时，不在源码包中复制 Python 依赖程序。

依赖归档来自既有本任务 Mooncakes 缓存；逐文件 SHA256 与安装源码核对，归档与原 LICENSE 附在 vendor/licenses。沒有修改归档上游源码。

## 生态定位与检索限制

实际读取可信本机 Mooncakes 索引中含 ODS/OpenDocument/spreadsheet/markitdown/XLSX 的条目。它是检索快照，不能证明当前注册表没有新项目。

- [ZSeanYves/markitdown README](https://github.com/ZSeanYves/markitdown/blob/main/README.mbt.md)：本次实际查到 Office/ODF 读取支持 ods，输出 Markdown/Debug/RAG；本地索引发布条目为0.5.3，而 README 主分支自述0.8开发线。不能混为一个已发布版本。它解决已有文件读取，MoonODS生成文件，无性能优于它的实测结论。
- [moonbitlang/office.mbt](https://github.com/moonbitlang/office.mbt)：实际 README表列 mbtexcel 为 XLSX读写，不是ODS生成声明。相关索引：mbtexcel0.2.1、office0.2.1、office-lib0.6.2。
- 本地索引还发现 bobzhang/spreadsheet 与 vectie/moonleaf 的 spreadsheet/OOXML 相关能力；未实际运行这些竞品，不声称彻底无重叠。

原创部分为 MoonODS类型API、限制政策、ODF serializer、固定路径 ZIP封装和测试。复用依赖有独立许可。是否认可为新生态项目仍由官方审核，不能只以语言不同或名称不同证明。

## 活动核对与剩余缺口（完整续读）

- [2026官方页](https://moonbitlang.github.io/Hackathon2026/)：实际下载前端与读完整中文文案。十月最多提交3次；10月31日为报名/验收截止；150启动和350完成支持各需审核。不保证个人净到账1500。群公告“每人单月最多3项目、10/1开放”来自用户已核证据，非本任务重新获取截图。
- [章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd)：本机浏览器复制全文，完整阅读11章、附录一/二及表格文字；页面标注9月27日修改。§5.1列出终验九条与原句“申报书务必人工撰写”；§8十月表截至10/24，与官网10/31冲突。§5.1指向赛事群通知，最终时刻待官方确认，内部按10/24前准备。§3.2原则上一项目与十月表单及用户已核群公告措辞不同，不自行统一解释。
- [十月报名表](https://bxup9uklfcb.feishu.cn/share/base/form/shrcnWUMlgpbwHaXgzV7HmNhNhg)：公开服务端快照实际读取全部16字段、说明、选项及条件。页面明示提交三次、可重复修改；新项目附件明确至少3完整场景、至少10有效commits、一页以内Markdown、“不要使用 AI 编写”。当前十月要求已核，不从九月推断。未填写、上传或提交。
- [诚信承诺](https://bxup9uklfcb.feishu.cn/wiki/GKDswxuptiJRcxkzPgZcw1J6nAd)：浏览器复制并完整阅读五部分，涉及身份/账户、实际独立贡献、推荐关系、核验及违规责任；未同意或签署。

详见RULES_REVIEW_ZH及验收矩阵；取证方法与摘要在`evidence/rules-review.json`。原始表单HTML含临时跳转token，完整章程/承诺工作副本均留在仓库外研究目录，不纳入源码ZIP或重新授权MIT。仅发布事实摘要与官方链接。

公开远端、mooncakes发布、报名、签署或个人材料均未执行。所有申报参考明确为 AI辅助事实，用户需独立理解并人工形成最终申报。

## 本地模块消费机制（2026-10-01实际查证）

- [Moon模块配置](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html) Dependency Management 与 Publishing Files：实际读取moon.work优先本地成员、版本字段在workspace忽略，以及.moonignore替代同目录.gitignore过滤候选包。
- [Workspace Support](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)：独立模块本地消费使用官方workspace机制；SDK本机实际运行结果另有命令日志，文档当前版本本身不代表旧SDK支持全部功能。

## 已装Excel实读

2026-10-01使用既有Microsoft Excel16.113.3、系统osascript读取四个自制无宏ODS；常规20组通过、整体PARTIAL。旧32768字截断后实现收紧至32767，修正后完整读取。公元0001年异常与绝对毫米列宽未校准保留；无LibreOffice实测或新增安装。未保存，输入SHA不变；Excel实际readOnly=false，不能声称强制只读。原始读取及命令在`evidence/office-2026-10-01-fixed/`，详见OFFICE_COMPATIBILITY_ZH。

本轮再读ODF XML§18.3.14/§19.374日期及§20.254固定列宽/§18.3.26正长度和对应RNG定义，默认日期/毫米属性符合规范。新增来源：[Microsoft日期系统](https://support.microsoft.com/en-us/excel/date-systems-in-excel)、[Excel限制](https://support.microsoft.com/en-us/excel/excel-specifications-and-limits)、[VBA Range.Width](https://learn.microsoft.com/en-us/office/vba/api/excel.range.width)、[W3C XML Schema date](https://www.w3.org/TR/xmlschema-2/#date)。实际读取正文；支持极早日期属Excel范围差异的推断。VBA的point约定不能直接证明Mac JXA单位，既有Excel.sdef的range.width没有单位说明。本轮未启动Office或取焦点。只分发事实摘要/链接，不复制第三方文档整篇。
