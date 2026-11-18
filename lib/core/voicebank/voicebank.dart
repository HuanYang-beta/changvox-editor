import 'dart:io';

/// oto.ini 中一行切片信息的简化表示。
class OtoEntry {
  const OtoEntry({
    required this.fileName,
    required this.alias,
    required this.offsetMs,
    required this.loopStartMs,
    required this.loopEndMs,
  });

  /// WAV 文件名、别名，以及本原型保留的 offset 和循环点参数（毫秒）。
  final String fileName;
  final String alias;
  final double offsetMs;
  final double loopStartMs;
  final double loopEndMs;
}

/// 已加载的 UTAU 声库：目录、歌手名称和所有 oto 切片。
class Voicebank {
  const Voicebank({
    required this.directory,
    required this.name,
    required this.entries,
  });

  final Directory directory;
  final String name;
  final List<OtoEntry> entries;

  /// 通过 oto 别名查找切片；找不到时返回 null。
  OtoEntry? entryFor(String alias) {
    for (final entry in entries) {
      if (entry.alias == alias) return entry;
    }
    return null;
  }

  /// 读取 character.txt 的歌手名和 oto.ini 的切片清单。
  static Future<Voicebank> load(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('Voicebank directory does not exist.', path);
    }
    final otoFile = File('${directory.path}${Platform.pathSeparator}oto.ini');
    if (!await otoFile.exists()) {
      throw FileSystemException('oto.ini was not found in the selected directory.');
    }
    final characterFile =
        File('${directory.path}${Platform.pathSeparator}character.txt');
    final pathParts = directory.path
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .toList();
    var name = pathParts.isEmpty ? directory.path : pathParts.last;
    if (await characterFile.exists()) {
      // character.txt 通常用 name=歌手名 描述声库名称。
      for (final line in await characterFile.readAsLines()) {
        final separator = line.indexOf('=');
        if (separator > 0 && line.substring(0, separator).trim() == 'name') {
          name = line.substring(separator + 1).trim();
          break;
        }
      }
    }

    final entries = <OtoEntry>[];
    // oto.ini 每行结构为 文件名=别名,offset,前置空白,重叠,预发音,后置空白,循环点,循环终点。
    for (final line in await otoFile.readAsLines()) {
      if (line.trim().isEmpty || line.trimLeft().startsWith(';')) continue;
      final separator = line.indexOf('=');
      if (separator < 0) continue;
      final fileName = line.substring(0, separator).trim();
      final fields = line.substring(separator + 1).split(',');
      if (fields.isEmpty) continue;
      // 声库格式字段不完整或数字不可解析时，原型暂按 0 处理。
      double numberAt(int index) =>
          index < fields.length ? double.tryParse(fields[index].trim()) ?? 0 : 0;
      entries.add(OtoEntry(
        fileName: fileName,
        alias: fields[0].trim(),
        offsetMs: numberAt(1),
        loopStartMs: numberAt(6),
        loopEndMs: numberAt(7),
      ));
    }
    return Voicebank(directory: directory, name: name, entries: entries);
  }
}
