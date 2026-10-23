# 独立范围审查（核心增量未交付）

独立只读agent核对原main3772f50、markitdown和mbtexcel公开源码，未修改代码或运行应用验证。

- 原有Value、formula+cache、Sheet编辑/merge可以复用，但package.mbt仅writer，没有reader入口。
- markitdown确有ODS text/formula/merge/repeat内部读取，且README说明internal不是consumer API；不能声称没有读取能力。类型化编辑写回及显式损失是可提出的差异，必须由外部闭环证明。
- mbtexcel已有XLSX读写公共API，CellValue没有Date/Empty直接分支，需要日期系统与空值映射。首轮拒绝公式跨格式转换，或用户明确选择cache-only并逐格诊断。
- 外部公式无缓存不能被当前Cell.formula表示；首轮明确拒绝，不能假造值。重复/解压/XML实体必须在reader入口有界；Python验证器不是reader实现。
- 必须使用有许可/hash/内容profile的真实外部ODS，受支持格编辑后独立语义核读，稳定LibreOffice隔离profile开存，以及MoonBit真实调用mbtexcel并重读XLSX。

本轮仅修正状态文档并给出上述最小范围；外部读改写和跨格式消费尚未实现。独立结论：**初审指出的ODS增量价值问题仍未解决。**SDK/工具环境阻塞见evidence/review-20261014，不把旧Linux/Dev/注册表通过移用为本轮新能力证据。
