# MoonODS 0.2.0发行快照

模块`sundaysebasidian-byte/moonods`，版本`0.2.0`，MIT。原仓库为[MoonODS](https://github.com/sundaysebasidian-byte/moonods)。安装指令：

```sh
moon add sundaysebasidian-byte/moonods@0.2.0
moon view sundaysebasidian-byte/moonods@0.2.0 --json
```

发布前明确核对正式注册表仅有0.1.0；发布命令只允许一次实际提交。发布回执、准确SHA及注册表验证结果须分别记录；本文件在提交前不把打包消费成功冒称注册表已安装。

核心实现仍与已经通过CI的08cf0a1相同；此阶段补齐双后端消费者适配、准确版本安装说明和验证。JS与Wasm GC各执行同样31核心/API及5独立消费者测试，不合计为62个不同测试。三个消费者在两个后端各由两个进程生成ODS；宿主保存实际Bytes，再由odfpy及官方ODF1.3 RNG检查30类型值/9XML，并比较后端与进程间字节。

JS夹具按目标选择Node文件适配器；Wasm GC用MoonBit标准库Base64输出Bytes，由测试宿主解码落盘。首次夹具误编译JS外部函数，以及占位Wasm入口未调用场景导致deny-warn失败均保留在`evidence/release-020/preflight`。它们不是生产库读取/转换功能或整个库运行缺陷；核心没有FFI。JS文件写入例、Wasm GC消费、native/llvm/非GC wasm支持范围分别说明。

本地完整验收在`evidence/release-020/final/acceptance.json`，对应提交的远端结果见[Actions](https://github.com/sundaysebasidian-byte/moonods/actions/workflows/ci.yml)。正式注册表验收用`scripts/verify_registry_release.py`：新目录、空索引及包缓存、只复用已有SDK/core，不复制凭据、不用moon.work；核对安装全部文件与已验收候选逐字节一致，再运行双后端check/build/test及三场景输出。历史0.1.0脚本及fixture继续冻结，不将0.2.0报告冒充旧发行。

实际LibreOfficeDev证据保持10/3原范围：8固定无宏输入、33值、2合并、50保存格式属性PASS，整体PARTIAL；本阶段源ODS摘要对应这些已测输入。当前Excel、稳定Office、GUI/打印、绝对纸面毫米和其他未列后端未测。CI与注册表消费不调用Office，不冒称新应用实测。

包只包含库、示例、接口、说明及许可；证据、原始研究、用户材料、凭据、Library身份和开发缓存排除。原创MIT、core/zipc/flate Apache-2.0及OASIS原版权保持；AI辅助如实声明。本阶段没有赛事申请、个人表单、代签或禁止代写的人工最终Markdown。
