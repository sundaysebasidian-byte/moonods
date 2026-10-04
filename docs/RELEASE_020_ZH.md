# MoonODS 0.2.0正式发行记录

模块`sundaysebasidian-byte/moonods`，版本`0.2.0`，MIT。原仓库为[MoonODS](https://github.com/sundaysebasidian-byte/moonods)。安装指令：

```sh
moon add sundaysebasidian-byte/moonods@0.2.0
moon view sundaysebasidian-byte/moonods@0.2.0 --json
```

2026-10-04正式发布成功，服务器`200 OK`；注册表元数据明确返回版本和latest_version均为0.2.0。已发布源码快照：`4cd43f395b15164282e2a56c5e66c9aa2b95b750`。发布前该SHA的[CI 37178702277](https://github.com/sundaysebasidian-byte/moonods/actions/runs/37178702277)已completed/success，实际证据已下载并与本地源码、候选全部文件核对一致。

正式包共46文件，注册表checksum与已验收候选ZIP的SHA256均为`718a4b001190fe4bbf52ad9fb8fcc3f06c437a54c60080e0c478f5ad6af75b35`。空索引/包缓存的新消费目录、无moon.work、未复制登录凭据，从正式注册表安装后全部46文件逐字节与候选相同。JS/Wasm GC各check/build/test通过，各5消费测试/0失败；各三份ODS实际由odfpy核30类型值、官方RNG核9XML，两个后端各运行两进程且字节全部相同。正式报告见`evidence/release-020/registry/registry.json`，发布回执及注册表元数据见`evidence/release-020/publication/`。

首个发布调用因任务专用MOON_HOME没有登录文件而在本地失败，未上传；该失败日志保留。只读确认正式0.2.0尚不存在后，仅修正本次进程的MOON_HOME，复用此前发布0.1.0所用SDK中的已有登录，正常publish成功。没有新建登录、复制或手读凭据、修改全局环境，正常成功发布后不再重发。本记录及后续证据文档提交不改变注册表中已冻结的0.2.0字节；后续本地打包候选含更新文档，与该正式包不可混同。

核心实现仍与已经通过CI的08cf0a1相同；此阶段补齐双后端消费者适配、准确版本安装说明和验证。JS与Wasm GC各执行同样31核心/API及5独立消费者测试，不合计为62个不同测试。三个消费者在两个后端各由两个进程生成ODS；宿主保存实际Bytes，再由odfpy及官方ODF1.3 RNG检查30类型值/9XML，并比较后端与进程间字节。

JS夹具按目标选择Node文件适配器；Wasm GC用MoonBit标准库Base64输出Bytes，由测试宿主解码落盘。首次夹具误编译JS外部函数，以及占位Wasm入口未调用场景导致deny-warn失败均保留在`evidence/release-020/preflight`。它们不是生产库读取/转换功能或整个库运行缺陷；核心没有FFI。JS文件写入例、Wasm GC消费、native/llvm/非GC wasm支持范围分别说明。

发布前完整本地验收在`evidence/release-020/final/acceptance.json`，对应提交的远端结果见上述准确CI。正式注册表验收已使用`scripts/verify_registry_release.py`完成，命令和真实stdout/stderr保留；只复用已有SDK/core，不称全新机器或完全离线无缓存初始化。历史0.1.0脚本及fixture继续冻结，不将0.2.0报告冒充旧发行。

实际LibreOfficeDev证据保持10/3原范围：8固定无宏输入、33值、2合并、50保存格式属性PASS，整体PARTIAL；本阶段源ODS摘要对应这些已测输入。当前Excel、稳定Office、GUI/打印、绝对纸面毫米和其他未列后端未测。CI与注册表消费不调用Office，不冒称新应用实测。

包只包含库、示例、接口、说明及许可；证据、原始研究、用户材料、凭据、Library身份和开发缓存排除。原创MIT、core/zipc/flate Apache-2.0及OASIS原版权保持；AI辅助如实声明。本阶段没有赛事申请、个人表单、代签或禁止代写的人工最终Markdown。
