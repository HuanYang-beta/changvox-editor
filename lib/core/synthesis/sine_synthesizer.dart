import 'dart:math' as math;
import 'dart:typed_data';

import '../models/score.dart';

/// 用正弦波生成音符，主要用于检查乐谱时间和 WAV 导出管线。
class SineSynthesizer {
  const SineSynthesizer({this.sampleRate = 44100});

  final int sampleRate;

  /// 根据每个音符的音高、位置和长度生成一段浮点音频。
  Float32List render(Score score) {
    // 找到最后一个音符的结束位置，决定整段音频需要多少采样。
    final endTick = score.notes.fold<int>(0, (end, note) {
      final noteEnd = note.pos + note.dur;
      return noteEnd > end ? noteEnd : end;
    });
    // tick 换算秒：每拍 60/BPM 秒，每拍 480 tick。
    final totalSamples = (endTick * 60 / (score.bpm * 480) * sampleRate).ceil();
    final output = Float32List(totalSamples);
    for (final note in score.notes) {
      // MIDI 音高转频率：69 对应 A4=440Hz，每升一个半音乘以 2^(1/12)。
      final start = (note.pos * 60 / (score.bpm * 480) * sampleRate).round();
      final length =
          (note.dur * 60 / (score.bpm * 480) * sampleRate).round();
      final frequency = 440 * math.pow(2, (note.tone - 69) / 12);
      // 把这个音符的正弦波写到总缓冲区对应的位置。
      for (var i = 0; i < length && start + i < output.length; i++) {
        output[start + i] +=
            0.25 * math.sin(2 * math.pi * frequency * i / sampleRate);
      }
    }
    // 多个音符重叠时相加可能超过音频允许范围，因此最后限制振幅。
    for (var i = 0; i < output.length; i++) {
      output[i] = output[i].clamp(-1.0, 1.0).toDouble();
    }
    return output;
  }
}
