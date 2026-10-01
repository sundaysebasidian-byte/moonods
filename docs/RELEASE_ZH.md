# MoonODS 0.1.0 发行记录

公开 GitHub 与首发 Mooncakes 已获用户明确批准。此文件记录工程事实，不是人工申报书或官方验收结论。

| 项目 | 当前状态 |
|---|---|
| 公开仓库 | **已公开**；https://github.com/sundaysebasidian-byte/moonods |
| 远端 CI | **修复后PASS**；首发6dced9e，运行36850277453 |
| Mooncakes 0.1.0 | **已发布**；sundaysebasidian-byte/moonods@0.1.0，服务器200 OK |
| 独立注册表消费 | **PASS**；空索引/包缓存真实下载，41文件同首发候选，4消费测试/30类型值/9XML |
| 隐私/许可 | 首发前核查通过，见 evidence/publication/privacy-license-review.json |
| 人工申报/签署 | 未执行；用户自行理解、撰写、报名及提交个人材料 |

本轮修复 `.moonignore`：从源码 ZIP 再打包时排除 SOURCE_STATE、Git 历史文本和 bundle，避免验收元数据进入安装包。先前换目录复现的核心25项和独立消费4项通过，但候选多出这三份文件；该包内容一致性失败保留，不当作整个交付通过。

Excel 16.113.3 常规20组通过、整体 **PARTIAL**；0001年显示缺口及毫米绝对列宽 **UNRESOLVED** 保留。新增日期诊断 ODS 未做原生Office实读。LibreOffice、Numbers、WPS **NOT TESTED**。详见验收矩阵及 OFFICE_COMPATIBILITY_ZH。

Mooncakes 内容在发布时固定；后续仓库新增的发行结果文档/证据不代表已发布包字节变化。记录发布候选全部文件的摘要与实际注册表下载逐文件比较，核心源码必须一致。

首轮真实CI [`36850050995`](https://github.com/sundaysebasidian-byte/moonods/actions/runs/36850050995)，提交 `8629b91203a4ecbeae721724439797bf7decdc9a`：SDK/Node/Python准备通过，依赖核对因 `.mooncakes` 尚未解析而失败；`moon update` 只更新索引。现将显式 `moon check` 解析依赖放在逐文件摘要校验之前，保持全部核对与测试标准。原始失败日志保留。源码ZIP换目录复现25+4通过，候选41份文件全部一致，见 evidence/publication/source-reproduction-summary.json。

## 首发与注册表验证结果

首发源码提交：`6dced9ed5798a7179d5259bde95145cc994f85df`。真实Linux CI [36850277453](https://github.com/sundaysebasidian-byte/moonods/actions/runs/36850277453) **success**，报告及原始日志在 `evidence/publication/ci-publish-sha/`：25核心/API、4独立候选消费、RNG/odfpy/ZIP及确定性通过。首轮失败运行保留。

`moon publish`正常命令退出0，服务器200 OK；发布器将包解压并下载固定zipc0.2.2/flate0.2.0后检查通过。`--frozen --dry-run`预检失败是解包临时目录无已安装依赖，不代表发布成功；已保留该失败记录。当前0.1.0已经发布，不重复上传。

随后 `scripts/verify_registry.py` 从**空索引及包缓存**启动，只复用既有SDK/bin/core/include，未复制凭据，不用moon.work。真实日志包含下载 `sundaysebasidian-byte/moonods@0.1.0`，安装的41份文件SHA256与首发候选全部相同；独立consumer的fmt/check/build/test通过，4测试/0失败。三场景两进程输出一致，odfpy核30类型值，官方RNG核9 XML，故意不一致公式缓存99完整保留，无求值器。记录在 `evidence/publication/registry/registry.json` 和 `release-summary.json`。不是全新机器，也没有再测原生Office。

本仓库发行结果文档/证据在首发之后补齐；Mooncakes中的README/发行进度是发布时的阶段快照。**已发布核心源码与当前核心相同**，逐文件发行摘要记录在候选/注册表报告中。后续本地重新打包用于交付审核，不冒称已上传包的新字节。公开包的功能版本仍为0.1.0。

源码ZIP包含完整真实Git历史、SOURCE_STATE、中文验收矩阵和测试证据。最终交付SHA及该SHA远端CI在ZIP补充文件 `evidence/delivery-ci/DELIVERY_CI.json` 及Library交付清单记录；该补充CI证据在最终提交之后产生，因此不冒称已在该提交树内。首发SHA和后续文档提交分别记录。
