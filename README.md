# 会听

会听是一款 macOS 实时转写应用。它同时采集本机麦克风与应用播放的声音，在本机识别中文和英文，并把文字持续写入 Markdown。识别模型随应用打包，转写可以离线完成。

## 安装与使用

**[下载 macOS 安装包](https://github.com/bobyunchaozhang/live-transcript/releases/latest)**。在发布页的 Assets 中按芯片选择 ZIP。

- **Apple 芯片（M 系列）**选择 `-macos-arm64.zip`。
- **Intel 芯片**选择 `-macos-universal.zip`，通用版也支持 Apple 芯片。

需要 macOS 15 Sequoia 或更新版本。请在 [Apple 的 macOS 15 兼容机型列表](https://support.apple.com/zh-cn/120282) 确认你的 Mac 型号。

1. 解压 ZIP，将「会听.app」移到「应用程序」文件夹后打开。也可以按下文从源码构建。
2. 点击「开始转写」。首次使用时，按 macOS 提示授予麦克风和系统音频访问权限。
3. 应用音频在左，本机麦克风在右。同一来源连续发言时，只在首段显示来源。时间戳使用北京时间（UTC+08:00）。
4. 点击「暂停」会释放两路采集，点击「继续」会接着写入同一份 Markdown。点击「停止」并确认后结束本次转写。使用顶部「访达」定位当前文件。

每次转写会在 `~/Library/Application Support/会听/转写/` 创建一份 UTF-8 Markdown。识别中的片段标为「待定稿」，确认后的文字会原位更新。会听只保存文字。使用 Mac 外放时，会听会用应用音频作为回声消除的参考，以减少麦克风中的重复转写。消除效果取决于外放音量、麦克风位置和环境反射。同一会议软件的远端发言共用「应用音频」标签。

当前打包脚本使用临时签名。通过网络下载的构建包可能触发 macOS 的开发者验证提示。关于首次打开的操作，见 [Apple 的打开 App 指南](https://support.apple.com/zh-cn/102445)。

## 从源码构建

安装带 macOS 15 或更高版本 SDK 的 Xcode 16 或更新版本。首次构建会下载约 146 MiB 的模型和运行库，并验证 SHA-256。开发时可使用 Codex 的 Run 按钮，或在项目根目录运行：

```sh
./script/build_and_run.sh
swift test
```

开发版输出到 `dist/LiveTranscript.app`。默认测试覆盖转写顺序、Markdown、回声消除和暂停／继续等逻辑。模型识别测试可通过 `HUITING_ASR_TEST_ASSETS` 指向已构建应用的 `Contents`，并通过 `HUITING_ASR_TEST_WAVS` 指向包含 `mandarin.wav` 和 `english.wav` 的 16 kHz 单声道 PCM 测试目录。

### 打包

```sh
./script/build_and_run.sh --package
./script/build_and_run.sh --package-arm64
```

`--package` 生成包含 arm64 和 x86_64 的通用版，产物为 `dist/universal/会听.app` 和 `dist/huiting-<版本>-macos-universal.zip`。`--package-arm64` 生成 Apple 芯片版，产物为 `dist/arm64/会听.app` 和 `dist/huiting-<版本>-macos-arm64.zip`。两种安装包均内置离线识别模型。

## 第三方组件

- [X-ASR](https://github.com/Gilgamesh-J/X-ASR) 提供中英文流式语音识别模型。
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 和 [ONNX Runtime](https://github.com/microsoft/onnxruntime) 提供模型推理。
- [SpeexDSP](https://github.com/xiph/speexdsp) 提供回声消除；源码许可随 `Sources/EchoDSP/Vendor` 提供。
- 应用图标使用 ByteDance IconPark 的 `voice-input` 图形，许可为 Apache 2.0。会听将原图形放在自制的 macOS 图标底板上，并将原图形另存为 PNG 用于空白页。出处和改动见 [IconPark 声明](script/ThirdParty/IconPark-NOTICE.txt)。

打包后的许可证和声明位于应用包内的 `Contents/Resources/ThirdParty`。
