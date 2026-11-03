# 原始脚本恢复工具

工具只读取原包，输出到本工程的 `recovered/` 和 `godot/content/`。剧情和媒体直接转换，不做内容改写。以下命令从工程根目录运行；PowerShell 传入含空格路径时需要加引号。完整脚本恢复产物已在本机 `recovered/yosuga/`，无需重新提取即可重新生成 story.json。

## 来源与依赖

- [yosugano 0.2](https://github.com/Senko-heart/yosugano)：CSX 反编译器；上游附有 GPL2/GPL3 许可文本。使用它将自己的 `system/yosuga.csx` 反编译为 `recovered/yosuga/`，并保留原 CSX 为 `recovered/yosuga.csx`。
- [GARbro 1.5.44](https://github.com/morkt/GARbro)：NOA / ERI / MIO 读取；主项目 MIT，编解码实现保留各自上游版权。将发行版依赖放在 `tools/GARbro/`，PowerShell 适配器加载其中 `GameRes.dll` 与 `ArcFormats.dll`。
- [Entis ERISA 官方 SDK 1.07e](https://www.entis.jp/eridev/download/index.html)，[SDK 下载](https://www.entis.jp/eridev/download/bin/erisa107e.lzh)：片头 ERIAnimation 解码。放在 `tools/erisa-official/erisalib/`，使用其原许可 `license.txt`。本补丁不分发 SDK、静态库或第三方工具二进制。
- Python 3，Pillow（离线 alpha 边界与视频采样），FFmpeg/FFprobe（PATH 可调用）；片头适配器构建需要 Visual Studio 2022 x86 C++ Build Tools。

## 提取与转换

`extract_noa.py ARCHIVE DESTINATION --names NAME...` 严格检查 NOA 目录、路径、原始文件块及长度，适用于未压缩项；结果带源文件 SHA-256。压缩的系统窗口资源使用 `extract_noa_packed.ps1 -Archive ... -OutputDirectory recovered/frame`。

本次提取资源清单在 `recovered/resource-source-status.json`。其中的 MIO 放入 `recovered/audio`，静态 ERI 与多帧 ERI 放入 `recovered/effects`，系统窗口放入 `recovered/frame`。原包中的片头 MEI 放入 `recovered/movie`。不要将整个原包覆盖解压到工程根目录。

```powershell
powershell -File tools/convert_eri.ps1 -InputDirectory recovered/effects -OutputDirectory godot/content -GarbroDirectory "$((Resolve-Path tools/GARbro).Path)"
powershell -File tools/convert_eri.ps1 -InputDirectory recovered/frame -OutputDirectory godot/content -GarbroDirectory "$((Resolve-Path tools/GARbro).Path)"
powershell -File tools/convert_animation.ps1
powershell -File tools/convert_mio.ps1
python tools/build_actor_metadata.py
python tools/restore_story.py
python tools/validate_restoration.py
```

`restore_story.py` 接受 `--sources`、`--content`、`--csx`、`--output`、`--report`；未知调用、条件或未闭合块直接失败，不能静默丢弃演出。命令、对话、分支位置均记录原始行号。原始译文 NUL 后的数据按原引擎字符串终止处理。重名 WAV/OGG 优先流式 OGG，原文件不删除。

## 片头

从 `tools/` 运行 `build_official_decoder.cmd`。如果本机 VS 路径不同，修改该脚本内的 vcvarsall 路径。`decode_frames.cpp` 默认须以 `USE_OFFICIAL` 构建，注意官方 `Open(file, preloadSize, flags)` 的参数顺序；不能用不兼容的旧 fork 替换。

将 `decode_official.exe ORIGINAL.mei recovered/opening-upright-video.ogv` 输出作为视频。音轨可由 `convert_mio.ps1 -InputDirectory recovered/movie -OutputDirectory recovered` 直接解码 MEI，按实际文件名选取其 OGG。然后使用 FFmpeg 将视频和音轨以 `-c copy` 合并到 `godot/content/opening.ogv`；最后运行 `python tools/validate_movie.py`。未保存剧情截图或采样画面，报告只含帧哈希与统计值。

## Godot 复验

先用 Godot 4.7.2 导入工程。`test_native_presentation.gd`、`test_actor_layout.gd`、`test_camera_layout.gd` 需要正常图形渲染，不能加 `--headless`。其余测试可无界面运行。

```powershell
godot --path godot --script res://test_native_presentation.gd --audio-driver Dummy -- --native-story="$((Resolve-Path godot/content/story.json).Path)"
godot --path godot --script res://test_actor_layout.gd --audio-driver Dummy -- --player-flow-test --actor-assets="$((Resolve-Path godot/content).Path)"
godot --headless --path godot --script res://test_native_player.gd --audio-driver Dummy -- --player-flow-test
godot --headless --path godot --script res://test_restored_media.gd --audio-driver Dummy -- --player-flow-test
godot --path godot --script res://test_camera_layout.gd -- --player-flow-test
godot --headless --path godot --script res://test_story_flow.gd
```

全集指令测试用人工纹理及加速时钟，真实媒体测试仅加载资源、播放片头，不遍历剧情画面。Windows 验证不能代替 iOS 构建和真机视觉验收。
