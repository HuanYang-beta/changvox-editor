# CHANGVOX UTAU 原型

基于 Flutter/Dart 的最小 UTAU 拼接合成原型。核心代码位于 `lib/core/`，不依赖 UI；界面位于 `lib/ui/`。

## 运行

需要本机已安装 Flutter SDK。项目不使用音频播放插件；渲染后的文件由系统播放器打开。

```sh
flutter create --platforms=linux .
flutter pub get
flutter run -d linux
```

应用中输入一个包含 `oto.ini` 的声库目录并加载，也可以输入 `.ustx` 文件路径读取歌曲。钢琴卷帘上拖动音符可更改位置/音高，拖音符右边缘可改时长；选中音符后可编辑别名。点击“渲染 UTAU WAV”或“渲染正弦 WAV”，文件分别写入当前工作目录下的 `exports/utau.wav` 和 `exports/sine.wav`。

UTAU 原型仅按 `oto.ini` 别名读取切片并使用 offset 截取；不进行音高变换、循环延音或交叉淡化。USTX 按 480 ticks/四分音符解释音符位置及时长，只读取第一个轨道、第一个 part 和全局 tempo。

本原型通过文本路径访问本机文件，尚未实现文件选择器；`oto.ini` 按 UTF-8 读取。
