# 游戏资源放置说明

本版本采用**资源随应用一起打包**的方式。公开仓库提供完整播放器源码、工程配置、中文字体和项目界面素材；原作剧情与媒体由使用者自行准备。仅有原游戏安装目录还不够，本工程读取的是已经转换好的 JSON、PNG、OGG／WAV 和 OGV 数据，不会直接读取原游戏封装格式。

## 正确目录

```text
godot/
  project.godot
  content/
    story.json
    chapter_catalog.json
    ... 对应的图片、音频、动画帧和视频
```

`story.json` 必须是本项目兼容的完整 schema 2 数据。只复制这个 JSON 而不复制其中引用的媒体，仍无法正常运行。

## 从已有完整工程准备

在你自己的兼容工程中找到 `godot/content/`，将整个目录复制到本工程同名位置，保留原文件名和大小写。不要覆盖本版本的 `.gd` 脚本。首次用 Godot 打开后，等待它重新生成导入缓存；无需复制旧 `.godot/` 缓存。

## 从已经持有的本项目资源 ZIP 准备

如果你已有此前生成的 `Yosuga-resources.zip`：在 Mac 上解压，里面有 `pack.json` 和 `content/`。将**内层 `content/` 目录**复制到本工程的 `godot/content/`，`pack.json` 不必复制。这个操作在构建前完成，不是在 iPhone 中导入。

如果你持有完整工程 ZIP，找到其内层 `YosugaMobile/godot/content/` 并复制。文件夹可能有不同外层名称，以包含 `story.json` 的这一层为准。

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
