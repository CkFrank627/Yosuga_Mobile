# 本次整理的验证记录

环境：Windows，Godot 4.7.2。日期：2026-11-02。

此目录保存本次重新检查的输出；不是把历史日志当作本次测试。运行测试时使用本机准备的完整资源，公开仓库不包含这些原作数据。

| 检查 | 结果 | 输出 |
| --- | --- | --- |
| 工程文件、脚本静态依赖、完整剧情的 19,361 项资源路径 | PASS | [source-check.log](source-check.log) |
| 公开源码 ZIP 解压、无原作资源、缺失资源诊断、中文文档与链接 | PASS | [source-distribution.log](source-distribution.log) |
| 演出播放器集成 | PASS | [native-player.log](native-player.log) |
| 完整资源标题启动、新游戏、10 次对白推进、实际舞台渲染 | PASS | [full-startup.log](full-startup.log) |
| 浅色／深色 RGB 与透明度、比例组合、独立预览、设置交互 | PASS | [color-modes.log](color-modes.log) |

运行检查复用了本机相同资源的 Godot 导入缓存；缓存不随源码提交，用户首次打开工程时仍须等待 Godot 导入。此次没有执行整部剧情逐句通关，也没有执行 Mac/Xcode 编译。签名及 iPhone 安装仍需按[中文教程](../../docs/IOS-EXPORT.zh-CN.md)在 Mac 完成。
