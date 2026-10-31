# MoonODS 0.5.0 发行候选

状态：源码版本准备完成；未取得 Mooncakes 0.5.0 发布及精确安装回执，不标为已发布。

## 范围与迁移

运行时代码基于默认分支 `562c34d0dff4bbd00f293945ff4190f4ec04bedb`；本版本准备仅修改模块版本、README 与本说明，不改变读写实现。相对 0.4.0，纳入 XML 名称/编码、内部 DTD 与实体、xml:id 诊断、manifest 与附加部件处理、精确物理布局、类型词法规范化及宿主 I/O 预检等已公开修订。依赖继续固定 `moonbit-community/flate@0.9.0`。

采用 minor 版本表达新增 API 与更严格的词法行为：布尔词法仅接受规范的 true/false，不再接受 1/0；物理尺寸及类型规范化规则见 README。导入仍须显式接受损失，扩展类型和基础格式另行开启。非有限数值仍不支持，合法超范围输入不等于无效 ODF。

## 标准与验证边界

[ODF 逐项回应](review-20261031/RESPONSE.zh-CN.md) 与 [实施定义审计](review-20261031/IMPLEMENTATION_DEFINED.zh-CN.md) 随源码保留。123 项为关键词条款盘点，不是全部 SHALL 的认证；不声明完整 ODF/XML 认证、通用公式重算或完整 Office/视觉保真。

原运行时代码的默认分支 [检查](https://github.com/sundaysebasidian-byte/moonods/actions/runs/41214105398) 与 [fresh clone](https://github.com/sundaysebasidian-byte/moonods/actions/runs/41214105371) 已通过，不冒充新发行候选或新包独立验收。旧 170/182/189 阶段与 GUI 证据保持历史版本归属，未新增 Microsoft Office 实测。

## 发布门槛

候选提交 CI、实际包文件清单、官方发布回执及干净消费者精确安装 `sundaysebasidian-byte/moonods@0.5.0` 分别核验。源码通过不代表新包已发布或已安装。MIT、依赖许可与来源范围保持不变。
