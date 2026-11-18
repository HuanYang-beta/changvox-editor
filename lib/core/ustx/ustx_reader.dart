import 'dart:io';

import 'package:yaml/yaml.dart';

import '../models/note.dart';
import '../models/score.dart';

/// USTX（YAML）最小读取器，只提取本原型需要的 BPM 和音符数据。
class UstxReader {
  const UstxReader();

  /// 从磁盘读取文本，再交给 parse 负责解释 YAML 内容。
  Future<Score> readFile(String path) async {
    final source = await File(path).readAsString();
    return parse(source);
  }

  /// 读取 tracks[0].parts[0].notes，不处理表达式、其他轨道或其他 part。
  Score parse(String source) {
    final document = loadYaml(source);
    if (document is! Map) {
      throw const FormatException('USTX root must be a YAML mapping.');
    }
    final root = _toStringMap(document);
    final bpm = _readBpm(root);
    final tracks = root['tracks'];
    // USTX 可能没有轨道或 part；此时返回带 BPM 的空乐谱。
    if (tracks is! List || tracks.isEmpty || tracks.first is! Map) {
      return Score(bpm: bpm);
    }
    final track = _toStringMap(tracks.first as Map);
    final parts = track['parts'];
    if (parts is! List || parts.isEmpty || parts.first is! Map) {
      return Score(bpm: bpm);
    }
    final part = _toStringMap(parts.first as Map);
    final rawNotes = part['notes'];
    if (rawNotes is! List) return Score(bpm: bpm);

    final notes = <Note>[];
    for (final rawNote in rawNotes) {
      if (rawNote is! Map) continue;
      final item = _toStringMap(rawNote);
      // USTX 的 position/duration 是 tick，tone 是 MIDI 音高。
      notes.add(Note(
        pos: _number(item['position'], 'position').round(),
        dur: _number(item['duration'], 'duration').round(),
        tone: _number(item['tone'], 'tone').round(),
        lyric: item['lyric']?.toString() ?? '',
      ));
    }
    return Score(notes: notes, bpm: bpm);
  }

  /// 兼容常见的 tempo、bpm 和 tempos 写法；原型只采用一个全局速度。
  double _readBpm(Map<String, dynamic> root) {
    final tempo = root['tempo'] ?? root['bpm'];
    if (tempo is num) return tempo.toDouble();
    if (tempo is Map) {
      final map = _toStringMap(tempo);
      final bpm = map['bpm'] ?? map['tempo'];
      if (bpm is num && bpm > 0) return bpm.toDouble();
    }
    final tempos = root['tempos'];
    if (tempos is List && tempos.isNotEmpty && tempos.first is Map) {
      final first = _toStringMap(tempos.first as Map);
      final bpm = first['bpm'] ?? first['tempo'];
      if (bpm is num && bpm > 0) return bpm.toDouble();
    }
    return 120;
  }

  /// 读取必需的数字字段；缺失或格式错误时抛出可见错误。
  double _number(Object? value, String field) {
    if (value is num) return value.toDouble();
    throw FormatException('USTX note is missing numeric "$field".');
  }

  /// YAML 解析结果的键可能不是 String，统一转换后方便按字段名查找。
  Map<String, dynamic> _toStringMap(Map map) => {
        for (final entry in map.entries) entry.key.toString(): entry.value,
      };
}
