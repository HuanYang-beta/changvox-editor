import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/score.dart';
import '../voicebank/voicebank.dart';
import '../wav/wav_writer.dart';

/// 极简 UTAU 拼接合成器：按 lyric 找 oto 切片、截取并放到时间轴。
class UtauSynthesizer {
  const UtauSynthesizer({this.sampleRate = 44100});

  final int sampleRate;

  /// 渲染乐谱。不变调、不循环；切片不够长的部分会保持静音。
  Future<Float32List> render(Score score, Voicebank voicebank) async {
    // 输出至少覆盖最后一个音符的结束时间。
    final totalSamples = score.notes.fold<int>(0, (end, note) {
      final noteEnd = ((note.pos + note.dur) *
              60 /
              (score.bpm * 480) *
              sampleRate)
          .ceil();
      return noteEnd > end ? noteEnd : end;
    });
    final output = Float32List(totalSamples);
    // 同一个 WAV 可能被多个音符使用，缓存读取结果避免反复读磁盘。
    final cache = <String, Future<PcmWave>>{};
    for (final note in score.notes) {
      // lyric 必须与 oto.ini 中的别名一致。
      final entry = voicebank.entryFor(note.lyric);
      if (entry == null) {
        throw StateError('No voicebank alias found for "${note.lyric}".');
      }
      final file = File(
        '${voicebank.directory.path}${Platform.pathSeparator}${entry.fileName}',
      );
      final wave = await cache.putIfAbsent(
        file.path,
        () => _readWave(file),
      );
      // 输出时间轴用指定采样率；sourceStart 则按源 WAV 的采样率定位 offset。
      final start =
          (note.pos * 60 / (score.bpm * 480) * sampleRate).round();
      final desiredLength =
          (note.dur * 60 / (score.bpm * 480) * sampleRate).round();
      final offset = (entry.offsetMs * wave.sampleRate / 1000).round();
      final sourceStart = offset.clamp(0, wave.samples.length).toInt();
      // 按音符时长换算源文件最多可读多少采样，防止切片越界。
      final sourceLimit = math.min(
        wave.samples.length,
        sourceStart + desiredLength * wave.sampleRate ~/ sampleRate,
      ).toInt();
      final sourceLength = sourceLimit - sourceStart;
      // 如果源 WAV 的采样率与输出不同，按最近邻方式重采样到输出采样率。
      final outputLength = math.min(
        desiredLength,
        (sourceLength * sampleRate / wave.sampleRate).floor(),
      ).toInt();
      for (var i = 0; i < outputLength && start + i < output.length; i++) {
        final sourceIndex = sourceStart + (i * wave.sampleRate ~/ sampleRate);
        output[start + i] = wave.samples[sourceIndex];
      }
    }
    return output;
  }

  /// 读入 WAV 字节并解析成归一化的浮点采样。
  Future<PcmWave> _readWave(File file) async {
    return PcmWave.fromBytes(await file.readAsBytes());
  }
}
