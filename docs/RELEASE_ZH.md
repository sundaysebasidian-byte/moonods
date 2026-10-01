# MoonODS 0.1.0 发行记录

公开 GitHub 与首发 Mooncakes 已获用户明确批准。此文件记录工程事实，不是人工申报书或官方验收结论。

| 项目 | 当前状态 |
|---|---|
| 公开仓库 | 准备中；目标 https://github.com/sundaysebasidian-byte/moonods |
| 远端 CI | 尚未执行；不以本地通过替代 |
| Mooncakes 0.1.0 | 尚未发布；命名空间 sundaysebasidian-byte/moonods |
| 独立注册表消费 | 尚未执行；此前本地候选消费通过 |
| 隐私/许可 | 首发前核查通过，见 evidence/publication/privacy-license-review.json |
| 人工申报/签署 | 未执行；用户自行理解、撰写、报名及提交个人材料 |

本轮修复 `.moonignore`：从源码 ZIP 再打包时排除 SOURCE_STATE、Git 历史文本和 bundle，避免验收元数据进入安装包。先前换目录复现的核心25项和独立消费4项通过，但候选多出这三份文件；该包内容一致性失败保留，不当作整个交付通过。

Excel 16.113.3 常规20组通过、整体 **PARTIAL**；0001年显示缺口及毫米绝对列宽 **UNRESOLVED** 保留。新增日期诊断 ODS 未做原生Office实读。LibreOffice、Numbers、WPS **NOT TESTED**。详见验收矩阵及 OFFICE_COMPATIBILITY_ZH。

Mooncakes 内容在发布时固定；后续仓库新增的发行结果文档/证据不代表已发布包字节变化。记录发布候选全部文件的摘要与实际注册表下载逐文件比较，核心源码必须一致。
