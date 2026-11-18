import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/note.dart';
import '../../core/models/score.dart';
import '../../core/synthesis/sine_synthesizer.dart';
import '../../core/synthesis/utau_synthesizer.dart';
import '../../core/ustx/ustx_reader.dart';
import '../../core/voicebank/voicebank.dart';
import '../../core/wav/wav_writer.dart';
import 'piano_roll_painter.dart';

class EditorApp extends StatefulWidget {
  const EditorApp({super.key});

  @override
  State<EditorApp> createState() => _EditorAppState();
}

class _EditorAppState extends State<EditorApp> {
  // 卷帘显示 4 小节：每个四分音符 480 tick，一小节按 4 拍计算。
  static const _totalTicks = 1920;
  // 当前只显示 MIDI 48（C3）到 84（C6）之间的音高。
  static const _lowTone = 48;
  static const _highTone = 84;

  // 这些控制器保存输入框的内容，例如声库路径和音符别名。
  final _voicebankPath = TextEditingController();
  final _ustxPath = TextEditingController();
  final _lyric = TextEditingController(text: 'a');
  final _bpm = TextEditingController(text: '120');

  // 初次打开时放三个示例音符，方便不加载文件也能试正弦波渲染。
  final _score = Score(notes: [
    Note(pos: 0, dur: 480, tone: 60, lyric: 'a'),
    Note(pos: 480, dur: 480, tone: 64, lyric: 'a'),
    Note(pos: 960, dur: 480, tone: 67, lyric: 'a'),
  ]);

  // 声库为空表示还没加载；selectedNote 记录当前正在编辑的音符。
  Voicebank? _voicebank;
  Note? _selectedNote;
  String _status = '输入声库目录后加载；音符可拖动或拖右边缘调整时长。';

  // 拖动开始时先记下鼠标位置和音符原值，后续用差值更新音符。
  int? _dragStartTick;
  int? _dragStartTone;
  int? _noteStartPos;
  int? _noteStartTone;
  int? _noteStartDur;
  // true 表示拖的是音符右边缘；false 表示移动音符本身。
  bool _resizing = false;
  // 渲染期间禁用按钮，避免同时启动多个导出任务。
  bool _busy = false;

  @override
  void dispose() {
    // 页面关闭时释放输入框控制器占用的资源。
    _voicebankPath.dispose();
    _ustxPath.dispose();
    _lyric.dispose();
    _bpm.dispose();
    super.dispose();
  }

  /// 从用户输入的目录加载声库，并显示名称和 oto 切片数量。
  Future<void> _loadVoicebank() async {
    try {
      final bank = await Voicebank.load(_voicebankPath.text.trim());
      if (!mounted) return;
      setState(() {
        _voicebank = bank;
        _status = '已加载 ${bank.name}：${bank.entries.length} 个 oto 切片';
      });
    } catch (error) {
      _showError(error);
    }
  }

  /// 读取 USTX，把 tempo 和音符放进当前 Score，替换示例内容。
  Future<void> _loadUstx() async {
    try {
      final score = await const UstxReader().readFile(_ustxPath.text.trim());
      if (!mounted) return;
      setState(() {
        _score.bpm = score.bpm;
        _score.notes
          ..clear()
          ..addAll(score.notes);
        _bpm.text = score.bpm.toStringAsFixed(0);
        _selectedNote = _score.notes.isEmpty ? null : _score.notes.first;
        if (_selectedNote != null) _lyric.text = _selectedNote!.lyric;
        _status = '已读取 USTX：${score.notes.length} 个音符，'
            '${score.bpm.toStringAsFixed(1)} BPM';
      });
    } catch (error) {
      _showError(error);
    }
  }

  /// 根据按钮选择合成方式，最后统一写出 16-bit PCM WAV。
  Future<void> _render({required bool useUtau}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final Float32List samples;
      if (useUtau) {
        // UTAU 合成要先加载声库；它会按每个音符的 lyric 找切片。
        final voicebank = _voicebank;
        if (voicebank == null) {
          throw StateError('请先加载 UTAU 声库。');
        }
        samples = await const UtauSynthesizer().render(_score, voicebank);
      } else {
        // 正弦波不需要声库，用来检查音符和 WAV 写入管线是否正常。
        samples = const SineSynthesizer().render(_score);
      }
      // 输出目录相对于启动应用时的当前工作目录。
      final outputDirectory = Directory('exports');
      await outputDirectory.create(recursive: true);
      final name = useUtau ? 'utau.wav' : 'sine.wav';
      await File('${outputDirectory.path}/$name')
          .writeAsBytes(floatToWav(samples), flush: true);
      setState(() => _status = '已导出 ${outputDirectory.path}/$name');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 同时更新状态文字并弹出提示，便于看到失败原因。
  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _status = '操作失败：$error');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失败：$error')),
    );
  }

  /// 在时间轴开头添加一个四分音符；之后可以拖到想要的位置。
  void _addNote() {
    final note = Note(
      pos: 0,
      dur: 480,
      tone: 60,
      lyric: _lyric.text.trim().isEmpty ? 'a' : _lyric.text.trim(),
    );
    setState(() {
      _score.notes.add(note);
      _selectedNote = note;
    });
  }

  /// 找到鼠标按下位置对应的音符，并记住拖动开始时的状态。
  void _onPanStart(DragStartDetails details, Size size) {
    // 横坐标按比例换算成 tick；纵坐标换算成 MIDI 音高。
    final tick = (details.localPosition.dx / size.width * _totalTicks).round();
    final tone = _highTone -
        (details.localPosition.dy /
                size.height *
                (_highTone - _lowTone + 1))
            .floor();
    Note? hit;
    // 从后往前找，让重叠时绘制在上面的音符优先被选中。
    for (final note in _score.notes.reversed) {
      if (tick >= note.pos - 20 &&
          tick <= note.pos + note.dur + 20 &&
          (tone - note.tone).abs() <= 1) {
        hit = note;
        break;
      }
    }
    setState(() {
      _selectedNote = hit;
      if (hit == null) return;
      _lyric.text = hit.lyric;
      _dragStartTick = tick;
      _dragStartTone = tone;
      _noteStartPos = hit.pos;
      _noteStartTone = hit.tone;
      _noteStartDur = hit.dur;
      // 鼠标落在音符右端附近时，进入改时长模式。
      _resizing = (tick - (hit.pos + hit.dur)).abs() <= 40;
    });
  }

  /// 按鼠标移动距离更新音符。位置/时长吸附到 30 tick 的网格。
  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final note = _selectedNote;
    if (note == null ||
        _dragStartTick == null ||
        _dragStartTone == null ||
        _noteStartPos == null ||
        _noteStartTone == null ||
        _noteStartDur == null) {
      return;
    }
    final tickDelta = (details.localPosition.dx / size.width * _totalTicks)
        .round() - _dragStartTick!;
    final tone = _highTone -
        (details.localPosition.dy /
                size.height *
                (_highTone - _lowTone + 1))
            .floor();
    final toneDelta = tone - _dragStartTone!;
    setState(() {
      if (_resizing) {
        // 调整时长时保持音符起点不动，并至少保留 30 tick。
        note.dur = ((_noteStartDur! + tickDelta) / 30).round() * 30;
        if (note.dur < 30) note.dur = 30;
      } else {
        // 普通拖动同时改位置和音高；位置不能拖到 0 tick 之前。
        note.pos = ((_noteStartPos! + tickDelta) / 30).round() * 30;
        if (note.pos < 0) note.pos = 0;
        note.tone =
            (_noteStartTone! + toneDelta).clamp(_lowTone, _highTone).toInt();
      }
    });
  }

  /// 拖动结束后清空临时数据，下次拖动会重新记录起点。
  void _onPanEnd(DragEndDetails details) {
    _dragStartTick = null;
    _dragStartTone = null;
    _noteStartPos = null;
    _noteStartTone = null;
    _noteStartDur = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CHANGVOX UTAU 原型')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 第一行：本机文件路径输入，以及加载声库/打开 USTX 按钮。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _voicebankPath,
                    decoration: const InputDecoration(
                      labelText: 'UTAU 声库目录（含 oto.ini）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _loadVoicebank,
                  child: const Text('加载声库'),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _ustxPath,
                    decoration: const InputDecoration(
                      labelText: '.ustx 文件路径',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _loadUstx,
                  child: const Text('打开 USTX'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 第二行：BPM、当前音符别名和两种 WAV 渲染方式。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _bpm,
                    decoration: const InputDecoration(
                      labelText: 'BPM',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      final bpm = double.tryParse(value);
                      if (bpm != null && bpm > 0) _score.bpm = bpm;
                    },
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _lyric,
                    decoration: const InputDecoration(
                      labelText: '音符别名',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (_selectedNote != null) _selectedNote!.lyric = value;
                      setState(() {});
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addNote,
                  icon: const Icon(Icons.add),
                  label: const Text('添加音符'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _render(useUtau: true),
                  child: const Text('渲染 UTAU WAV'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _render(useUtau: false),
                  child: const Text('渲染正弦 WAV'),
                ),
                if (_busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // LayoutBuilder 取得卷帘实际宽度，拖动换算要用相同的尺寸。
            SizedBox(
              height: 440,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, 440);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) => _onPanStart(details, size),
                    onPanUpdate: (details) => _onPanUpdate(details, size),
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      size: size,
                      painter: PianoRollPainter(
                        notes: _score.notes,
                        selectedNote: _selectedNote,
                        totalTicks: _totalTicks,
                        lowTone: _lowTone,
                        highTone: _highTone,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // 显示加载、读取或导出结果；已加载声库时也列出所有别名。
            Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (_voicebank case final bank?)
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: bank.entries.length,
                  itemBuilder: (context, index) {
                    final entry = bank.entries[index];
                    return ListTile(
                      dense: true,
                      title: Text(entry.alias),
                      subtitle: Text(entry.fileName),
                      onTap: () {
                        _lyric.text = entry.alias;
                        if (_selectedNote != null) {
                          setState(() => _selectedNote!.lyric = entry.alias);
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
