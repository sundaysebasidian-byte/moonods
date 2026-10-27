# 来源与技术选择

- [OASIS ODF 1.3 Packages](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part2-packages/OpenDocument-v1.3-os-part2-packages.html)：mimetype、ZIP 与 manifest 约束。
- [OASIS ODF 1.3 Schema](https://docs.oasis-open.org/office/OpenDocument/v1.3/os/part3-schema/OpenDocument-v1.3-os-part3-schema.html)：类型、样式和表格 XML。测试 schema 由 scripts/fetch_schemas.py 从固定官方来源获取并校验哈希，不作为 MIT 成果分发。
- [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180.html)：CSV 引号和记录格式参考；另接受常见 LF 记录，要求等宽，不做自动编码或分隔符探测。
- [MoonBit workspace](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)：独立模块从本地源码消费；workspace 不等于注册表安装。
- [moonbit-community/flate](https://github.com/moonbit-community/flate)：压缩、解压与 CRC32。当前固定 0.9.0，原版源码归档及逐文件摘要见 DEPENDENCIES.lock.json；没有复制其他表格库实现。

MoonODS 自行实现类型模型、预算校验、ODS ZIP 封装和有界 XML/CSV 处理。核心返回 Bytes，不访问文件系统；JS 示例负责文件路径、读取和替换。选择数据型读取并逐项诊断损失，避免伪装成保真办公软件编辑器。

读取夹具由本项目合成 FODS 经 LibreOfficeDev 转换，生成来源见 tests/reader-fixtures；故障变体由相应脚本生成。无真实个人业务记录或第三方私人表格。

新公开树仅包含源码、运行配置、必要测试、许可和使用文档；历史审计资料与旧复现产物保持单独私有保存。0.4.0 已正式发布，源码与 registry 回执见[版本 PR #9](https://github.com/sundaysebasidian-byte/moonods/pull/9)。

本地读取兼容回归的 `tests/reader-fixtures/source/rich-text.fods` 是本项目原创 MIT 合成文件；LibreOffice 转换结果仅作为实验产物。官方 `LibreOffice/core` 固定样本单独下载并校验，不随源码或包重分发；来源、许可边界和摘要见 [读取兼容说明](docs/READER_COMPAT.zh-CN.md)。
