# Sources and attribution

本仓库公开播放器源码、中文字体及项目 UI，不包含原作剧情和媒体。字体许可证位于 `godot/fonts/OFL.txt`；`godot/ui/title-sky-v1.png` 是此前为本项目独立生成的标题界面背景。下文资源恢复工具为历史来源记录，相关第三方二进制、SDK 及原作数据均未随仓库分发。`tools/RESTORATION.md` 保留历史转换流程说明，本次仓库不包含其中提到的整套转换工具及依赖；运行本版请按 `docs/RESOURCES.zh-CN.md` 准备已有兼容数据。

2026-10-15 restoration dependencies:

- **yosugano 0.2** — https://github.com/Senko-heart/yosugano. Used locally to recover Cotopha scenario and engine scripts; upstream includes GPL2/GPL3 license texts. Not bundled in this patch.
- **GARbro 1.5.44** — https://github.com/morkt/GARbro. Used locally for NOA, ERI and MIO decoding; MIT project with codec-specific upstream notices. Its binaries and vendor sources are not bundled.
- **Entis ERISA SDK 1.07e** — https://www.entis.jp/eridev/download/index.html. Official ERIAnimation decoder used to convert the original movie; the SDK's license.txt applies. The patch includes our adapter source, not the SDK or linked executable.
- **FFmpeg / FFprobe** — https://ffmpeg.org. Used locally to encode Vorbis/Theora and verify media; no binaries are bundled.

Reproduction instructions are in `tools/RESTORATION.md`. Project code changes follow the existing GPL-2.0-only license; the original media retain their separate rights.

- **CSXTool** — https://github.com/RealMrWicked/CSXTool, Amanojaku and contributors, GPL-2.0. The CSX string-record and function-table layout was researched using this source. The importer is distributed under GPL-2.0-only. Exact reference revision is in `dependencies.lock.json`.
- **CSXtoXP3** — https://github.com/RealMrWicked/CSXtoXP3, MrWicked and contributors, GPL-2.0. The local chapter staging fixture is adapted from `dependencies/yosuga/00_z000.ks` or `00_z001.ks`. Its historical global line numbers are retained as `source_line_id`; dialogue is read from the user's local CSX, not fabricated or downloaded as translated text.
- **Yosuga Entis tools** — https://github.com/N0zoM1z0/yosuga-no-sora-entis-tools. Used locally for resource decoding. No standalone license file was present in the inspected revision; these scripts are kept as a pinned local checkout and are not bundled into the Mac transfer archive. The local importer patches bit-reader behavior in memory to discard consumed high bits and avoid quadratic integer growth. Vendor source files are unchanged.
- **Godot Engine** — https://godotengine.org, MIT. The Windows editor is a local development dependency, not part of the source transfer archive. Exported Godot binaries retain their applicable engine license requirements.
- **Noto Sans CJK SC Regular** — https://github.com/notofonts/noto-cjk, SIL Open Font License 1.1. The original static font is bundled at `godot/fonts/NotoSansCJKsc-Regular.otf`, with its license in `godot/fonts/OFL.txt`, including in iOS exports. Used for consistent Chinese glyph rendering across platforms.
- **Pillow / cffi** — build-time Python dependencies; not shipped in the source transfer archive.
- **Original game and Chinese patch** — local user-supplied data. Original assets, text, voices and music remain under their respective owners' rights. The GPL source license does not cover those assets.

The upstream Kirikiri iOS remake was inspected as a reference only. This prototype uses Godot rather than that runtime, and does not fetch its game-data releases.
