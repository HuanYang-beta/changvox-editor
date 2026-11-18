import 'package:flutter/material.dart';

import '../../core/models/note.dart';

/// 只负责把网格和音符画出来；鼠标拖动等交互由 EditorApp 处理。
class PianoRollPainter extends CustomPainter {
  const PianoRollPainter({
    required this.notes,
    required this.selectedNote,
    this.totalTicks = 1920,
    this.lowTone = 48,
    this.highTone = 84,
  });

  final List<Note> notes;
  final Note? selectedNote;
  final int totalTicks;
  final int lowTone;
  final int highTone;

  static const double ticksPerBeat = 480;

  /// CustomPainter 的绘制入口，size 是卷帘区域实际宽高。
  @override
  void paint(Canvas canvas, Size size) {
    // 将 tick 与 MIDI 音高分别线性映射到横向和纵向像素。
    final tickWidth = size.width / totalTicks;
    final rowCount = highTone - lowTone + 1;
    final actualRowHeight = size.height / rowCount;
    final background = Paint()..color = const Color(0xff171923);
    canvas.drawRect(Offset.zero & size, background);

    // 每 120 tick 画一条竖线，每 480 tick（1 拍）使用更亮的线。
    final grid = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xff343746);
    for (var tick = 0; tick <= totalTicks; tick += 120) {
      final x = tick * tickWidth;
      grid.color = tick % ticksPerBeat == 0
          ? const Color(0xff555a70)
          : const Color(0xff343746);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    // 每个 MIDI 音高画一行；C 音（MIDI 号是 12 的倍数）使用更亮的线。
    for (var tone = lowTone; tone <= highTone; tone++) {
      final y = (highTone - tone) * actualRowHeight;
      grid.color = tone % 12 == 0
          ? const Color(0xff555a70)
          : const Color(0xff292c38);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // 每个 Note 被画成矩形，当前选中的音符使用不同颜色。
    for (final note in notes) {
      final rect = Rect.fromLTWH(
        note.pos * tickWidth,
        (highTone - note.tone) * actualRowHeight,
        (note.dur * tickWidth).clamp(4, size.width).toDouble(),
        actualRowHeight - 1,
      );
      final isSelected = identical(note, selectedNote);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = isSelected
            ? const Color(0xffc7b5ff)
            : const Color(0xff8a78d6),
      );
      final text = TextPainter(
        text: TextSpan(
          text: note.lyric,
          style: TextStyle(
            color: isSelected ? const Color(0xff171923) : Colors.white,
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: mathMax(0, rect.width - 6));
      text.paint(canvas, Offset(rect.left + 4, rect.top + 2));
    }
  }

  /// 防止文本最大宽度为负数（例如音符宽度小于标签宽度时）。
  double mathMax(double a, double b) => a > b ? a : b;

  // 音符对象本身会被原地修改，简单起见每次更新都重新绘制。
  @override
  bool shouldRepaint(covariant PianoRollPainter oldDelegate) => true;
}
