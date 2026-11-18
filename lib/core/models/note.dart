/// 乐谱里的单个音符。
class Note {
  Note({
    required this.pos,
    required this.dur,
    required this.tone,
    required this.lyric,
  });

  /// 音符开始时间，单位是 tick；本原型用 480 tick 表示一拍。
  int pos;

  /// 音符持续时间，单位同样是 tick。
  int dur;

  /// MIDI 音高，例如 60 是中央 C（C4）。
  int tone;

  /// UTAU 声库中的别名，例如 "a"，用来查找对应的 WAV 切片。
  String lyric;
}
