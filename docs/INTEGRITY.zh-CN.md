# 版本来源与完整性检查

整理日期：2026-11-02。

## 指定 ZIP 的实际内容

`YosugaMobile-5-20261103T014931Z-1-001.zip` 大小为 **241,896 字节**，含 **40 个文件**：39 个受清单校验的文件，以及 `manifest-sha256.json` 本身。

ZIP 的 CRC 检查和 39 个文件的 SHA-256 清单核对均通过。但该 ZIP 是 **2026-10-22 浅色／深色模式增量补丁**，原本缺少 `project.godot`、主场景、`story_flow.gd`、`save_store.gd`、中文字体、标题页 UI 素材和完整游戏媒体，因此不能单独作为 Godot 工程运行。

## 本次补齐

以对应的 `YosugaMobile-full-project-Mac-2026-10-19.zip` 为基础补齐缺失工程文件，再覆盖你指定 ZIP 中的版本。保留所选版本的阅读、音量、比例、着色模式和章节目录实现；没有引入后续资源分离版的导入功能。

原补丁中的文件在本机准备目录中再次逐项核对，通过 39 项 SHA-256 校验。Git 对文本统一 LF 换行，因此 GitHub 上的文本字节哈希可能与原 ZIP 的 CRLF 文本不同，代码逻辑不因此改变。

公开仓库包含完整播放器源码、主场景、Godot／iOS 导出配置、中文字体及其许可证、项目 UI、中文教程和检查工具。原作游戏数据、原作媒体、编辑器缓存和签名文件均不提交。运行前须按[资源说明](RESOURCES.zh-CN.md)自备兼容数据。

## 检查范围

`tools/check_project.py` 检查必需工程文件和脚本的静态资源依赖；加上 `--require-content` 时，还检查本机完整剧情数据及其声明的 19,361 项资源路径。本次使用的本机数据为 306 章的 schema 2 数据。

本次实际运行结果见 [验证记录](../reports/verification/README.md)。源码检查、Windows 上的 Godot 运行验证，与 Mac 上的 Xcode 编译、签名是不同环节；本次不声称已经替用户执行 Mac 构建。

## 如何复查

1. 下载完整源码，按资源说明准备 `godot/content/`。
2. 在根目录运行 `python3 tools/check_project.py --require-content`。
3. 使用 Godot 4.7.2 打开 `godot/project.godot`，等待资源导入并运行。
4. 按[中文导出教程](IOS-EXPORT.zh-CN.md)在自己的 Mac 和 iPhone 上构建测试。

如果下载的是 GitHub 的源码 ZIP，缺少 `content/` 是公开源码包的预期状态；缺少 `project.godot` 或上述基础脚本则不是。
