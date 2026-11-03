# YosugaMobile：Godot / iOS 移植工程

中文视觉小说播放器，使用 Godot 构建，可在 Mac 上导出 Xcode 工程，再签名安装到自己的 iPhone。

## 从这里开始

| 你想做什么 | 阅读位置 |
| --- | --- |
| 第一步：准备缺少的游戏数据 | [资源放置说明](docs/RESOURCES.zh-CN.md) |
| 第二步：下载，在自己的 iPhone 上运行 | **[Mac → iPhone 中文导出教程](docs/IOS-EXPORT.zh-CN.md)** |


## 版本功能

- 阅读、自动播放、历史回看、存档与读档。
- 章节目录：按主线、穹线、奈绪线、瑛线、一叶线和初佳线分组。
- 背景音乐与角色语音独立音量；滑块仅拖动圆形滑块时改变值。
- 原始比例／自适应裁剪与预览；裁剪只影响背景，立绘大小保持不变。
- 默认浅色模式，以及保留旧画面质感的深色模式，均有独立预览。
- 对话框不透明度、经典／自设颜色、弹窗外点击关闭与触摸滚动。

## 运行条件

- **Godot 4.7.2 标准版**及相同版本的导出模板。使用已验证版本可减少兼容问题。
- iOS 构建需要 **Mac、Xcode 和 iPhone**；工程最低 iOS 版本为 16.0。
- 自备兼容的 `godot/content/` 游戏数据。公开源码包不包含原游戏剧情、图片、语音、音乐或视频。

完整流程：**准备资源 → Godot 本地预览 → 导出 iOS 工程 → Xcode 签名 → iPhone 安装**。从 GitHub 下载 ZIP 本身不能直接安装到 iPhone。

## 工程目录

```text
godot/
  project.godot          Godot 工程入口
  main.tscn             主场景
  player.gd             阅读器与设置
  native_presentation.gd 演出播放器
  front_menu.gd         标题页、音乐室、美术室
  story_flow.gd         剧情流程
  save_store.gd         存档
  fonts/                中文字体与字体许可证
  ui/                   项目界面素材
  content/              本机游戏数据，不提交到公开仓库
docs/                   中文教程
tools/check_project.py  检查源码和本机资源是否齐全
LICENSE                 GPL-2.0-only 许可证
THIRD_PARTY.md          第三方来源与许可说明
```

在工程根目录执行以下命令检查源码；Mac 上使用 `python3`：

```sh
python3 tools/check_project.py
```

放好资源后再检查可运行数据：

```sh
python3 tools/check_project.py --require-content
```

## 开源与分发

项目代码采用 [GPL-2.0-only](LICENSE)，随附字体采用 SIL OFL，原作资源不包含在代码许可证中。发布播放器源码不等于获得原作资源的再分发授权。

用户可以用自己的 Personal Team 构建真机测试版；免费签名需要定期重新签名安装。TestFlight／App Store 分发需要相应开发者会员及 Apple 审核。具体构建步骤见中文教程。
