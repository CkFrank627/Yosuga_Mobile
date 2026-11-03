# Mac 导出并安装到 iPhone：中文教程

适用于本仓库的 **YosugaMobile-5／2026-10-22 着色模式版**。本版把游戏数据一起导出进应用，安装后直接使用；

## 1. 准备工具和工程

1. 安装 Godot **4.7.2 标准版** （或者至少4.2以上），再在“编辑器 → 管理导出模板”安装 **同版本**模板。
2. 安装 Xcode，首次打开并完成组件安装、许可确认。在 Xcode → Settings → Locations 中选择已安装的 Command Line Tools。
3. 在 GitHub 仓库选择 **Code → Download ZIP**，解压到 Mac。本地目录名称可以不同，下文统一称“工程根目录”。
4. 确保[资源说明](RESOURCES.zh-CN.md)的资源准备完毕，可以看`godot/content/`确认它直接包含 `story.json`，而不是多嵌套一层 `content/content/`。

如需检查资源，在终端输入 `cd `（末尾有空格），把工程根目录从 Finder 拖入终端，回车。再执行：

```sh
python3 tools/check_project.py --require-content
```

**复制命令时只复制代码框内的命令，不要复制三个反引号或 `sh`。**如果命令需要路径，可把 Finder 中的文件拖入终端来填写，避免手打路径出错。

## 2. 在 Godot 中先运行一次

1. 启动 Godot，在项目管理器点击“导入”，选择 `godot/project.godot`。
2. 等待资源导入完成。首次处理大量图片和音频会较慢。
3. 按 **F5** 运行工程。
4. 确认能进入标题页、开始阅读，设置里有“画面着色”的浅色／深色预览。

如果报找不到 `story.json`、贴图、音频，先补齐资源。不要带着这些错误继续导出。

## 3. 填写 iOS 导出设置

打开“项目 → 导出”，选择已有的 **iOS** 预设；如果没有，点击“添加 → iOS”。

| 选项 | 如何填写 |
| --- | --- |
| Application → App Store Team ID | 随便输入一个十位数，比如：1234567890 |
| （它也许还会让你上传软件图标，随便上传一个就行）|
| Application → Bundle Identifier | 首次安装填写独有标识，例如 `com.unknown.yosugamobile` |
| Application → Export Project Only | 保持开启，只导出 Xcode 工程 |
| Application → Min iOS Version | 保持 16.0，或根据实际部署需求提高 |
| Short Version / Version | 展示版本／构建号；更新已安装版本时构建号递增 |

## 4. 导出 Xcode 工程

1. 在工程外新建空目录，例如桌面上的 `Yosuga-iOS-Export`。
2. 点击“导出项目”，在该目录中填写导出名称并保存。首次真机测试可以保留 Debug 导出。
3. 导出完成后，在导出目录中找到 `.xcodeproj`，双击用 Xcode 打开。若导出产物包含外层 ZIP，先解压它。

不要把导出目录放进 `godot/content/`，也不要把现成的 `.xcodeproj` 路径当成 Godot 工程入口。Godot 打开 `.godot` 工程文件；Xcode 打开 `.xcodeproj`。

## 5. 在 Xcode 签名并安装

1. 点击左侧蓝色工程图标，在 **TARGETS** 下选择应用目标。
2. 打开 **Signing & Capabilities**，勾选 **Automatically manage signing**。
3. Team 选择自己的 **Personal Team** 。
4. 若提示 Bundle Identifier 被占用，首次安装可改成自己的独有值；要覆盖已有应用时应先核对原标识和团队。
5. 用数据线连接 iPhone，解锁手机，按提示选择“信任此电脑” （或者不行的话，在启用手机的开发者模式并重启）。
6. 在 Xcode 顶部选择你的 **iPhone 名称**，不要选择模拟器或只有“Any iOS Device”的归档目标。
7. 点击 **▶ Run**，或按 **⌘R**，等待编译、签名和安装。
8. 若提示不信任开发者，在“设置 → 通用 → VPN 与设备管理”信任对应开发者后再打开。

Personal Team 可用于自己的设备测试。免费预置描述文件有效期为 7 天，到期后用原团队、原 Bundle ID 重新构建并覆盖安装（也就是再执行一遍：5. 在 Xcode 签名并安装）

## 6. 手机上检查这些操作

- 冷启动进入标题页，开始阅读，画面和语音正常。
- 章节目录能跳转，手动存档／读档正常。
- 背景音乐与角色语音可独立调节。
- 原始比例／背景裁剪、浅色／深色预览和实际画面相符。
- 对话框不透明度、自设颜色、列表快速滚动正常。
- 切到后台再回来、关闭后重开，设置和阅读进度正常。

本版的资源已经随应用安装，**不需要在手机上另外导入 ZIP**。

## 常见问题

| 现象 | 处理方法 |
| --- | --- |
| Godot 找不到字体、脚本、主场景 | 确认下载了本仓库完整源码，不是历史更新补丁；运行完整性检查 |
| `story.json` 或大量媒体缺失 | 按资源说明补齐 `godot/content/`，然后等待 Godot 重新导入 |
| 提示缺少导出模板 | 安装与 Godot 编辑器完全同版本的模板 |
| No profiles / Signing requires a development team | 登录 Xcode 账号，选择应用 Target、Team，并开启自动签名 |
| Bundle Identifier unavailable | 首次安装换用独有标识；覆盖旧版前先核对原团队和标识 |
| 手机不出现在运行设备里 | 解锁并信任，检查线缆和 Xcode 是否支持手机系统，完成设备准备 |
| 程序过几天打不开 | 免费签名到期；连接 Mac，用相同团队和标识重新 Run |
| 终端出现 `sh-3.2$` | 可能粘贴了 Markdown 反引号；先按 Control+C，必要时输入 `exit`，之后只粘贴命令正文 |

## 官方参考

- [Godot 4.7：导出 iOS](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html)
- [Apple：开发者账号与 Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- [Apple：TestFlight](https://developer.apple.com/testflight/)

本次整理在 Windows 完成，不能替代 Mac/Xcode 编译。本教程针对本版本的内置资源流程；后续资源分离版本的桥接步骤不适用于这里。
