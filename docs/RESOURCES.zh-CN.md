
通过网盘分享的文件：02-GameResources.zip
链接: https://pan.baidu.com/s/1Q3WX5nFg-__2GlqVTOxqeQ?pwd=hy8y 提取码: hy8y 复制这段内容后打开百度网盘手机App，操作更方便哦

# 游戏资源放置说明

本版本采用**资源随应用一起打包**的方式。公开仓库提供完整播放器源码、工程配置、中文字体和项目界面素材；**原作剧情与媒体从顶部的百度网盘链接下载！**。

## 正确目录（可以稍微自行检查一下，但是肯定不会出问题）

```text
godot/
  project.godot
  content/
    story.json
    chapter_catalog.json
    ... 对应的图片、音频、动画帧和视频
```

`story.json` 必须是本项目兼容的完整 schema 2 数据。只复制这个 JSON 而不复制其中引用的媒体，仍无法正常运行。

从一个Mac上下载 `Yosuga-resources.zip` 后请做以下步骤：在 Mac 上解压，里面有 `pack.json` 和 `content/`。将**内层 `content/` 完整目录**全部复制到本工程的 `godot/content/`，（`pack.json` 不必复制。）

以上操作必须在Mac上构建之前完成。

## 检查

在工程根目录运行：

```sh
python3 tools/check_project.py --require-content
```

如果缺少 `chapter_catalog.json`，但完整剧情及其他资源已经齐全，可用 Godot 命令行重建：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot --script build_chapter_catalog.gd
```

上面的 Godot 路径是假定安装在“应用程序”目录；如果安装位置不同，使用自己的实际可执行文件路径。重建目录不生成缺失的剧情或媒体。

## GitHub 中保存什么

`.gitignore` 排除了 `godot/content/`、导出产物、Godot 缓存和本机签名文件。请保留这一规则。资源由你在本机准备；不要误把含原作素材的完整运行包当作源码提交。

原作素材的授权与播放器的 GPL 许可证分别处理；本仓库不提供原游戏资源下载。
