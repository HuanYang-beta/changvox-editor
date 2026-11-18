import 'note.dart';

/// 一段简化乐谱：音符列表和全曲速度。
class Score {
  Score({List<Note>? notes, this.bpm = 120})
      : notes = notes ?? <Note>[];

  /// 可编辑的音符集合。
  final List<Note> notes;

  /// 每分钟拍数（Beats Per Minute），会用于把 tick 换算成秒。
  double bpm;
}
