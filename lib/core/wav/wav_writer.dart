import 'dart:typed_data';

/// 把 -1.0 到 1.0 之间的浮点采样转换成标准 16-bit PCM WAV 字节。
Uint8List floatToWav(Float32List samples, {int sampleRate = 44100}) {
  // 每个采样占 2 字节；WAV 文件头固定占 44 字节。
  final dataLength = samples.length * 2;
  final bytes = ByteData(44 + dataLength);

  // WAV 的标识字符串是 ASCII 字符，写入时每个字符占一个字节。
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  // RIFF/WAVE 文件头：描述文件长度、采样率、声道和采样位数。
  writeAscii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  // PCM 是整数格式。先限制振幅，再按正负范围分别映射到 16-bit 整数。
  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i].clamp(-1.0, 1.0);
    final value = sample < 0 ? (sample * 32768).round() : (sample * 32767).round();
    bytes.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// 从常见 WAV PCM 文件中读取采样，并转换成单声道浮点数。
class PcmWave {
  const PcmWave({required this.sampleRate, required this.samples});

  final int sampleRate;
  final Float32List samples;

  /// 解析 WAV 的 RIFF 块；支持 8/16/24/32-bit PCM 和 32-bit float。
  factory PcmWave.fromBytes(Uint8List data) {
    if (data.length < 44 || _ascii(data, 0, 4) != 'RIFF' ||
        _ascii(data, 8, 4) != 'WAVE') {
      throw const FormatException('Unsupported or invalid WAV file.');
    }
    final view = ByteData.sublistView(data);
    var offset = 12;
    var format = 0;
    var channels = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;
    var dataOffset = -1;
    var dataLength = 0;
    // RIFF 文件由多个块组成；fmt 描述音频格式，data 存放音频采样。
    while (offset + 8 <= data.length) {
      final chunkId = _ascii(data, offset, 4);
      final chunkLength = view.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      if (chunkStart + chunkLength > data.length) {
        throw const FormatException('Truncated WAV chunk.');
      }
      if (chunkId == 'fmt ') {
        if (chunkLength < 16) {
          throw const FormatException('Invalid WAV format chunk.');
        }
        format = view.getUint16(chunkStart, Endian.little);
        channels = view.getUint16(chunkStart + 2, Endian.little);
        sampleRate = view.getUint32(chunkStart + 4, Endian.little);
        bitsPerSample = view.getUint16(chunkStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkStart;
        dataLength = chunkLength;
      }
      offset = chunkStart + chunkLength + (chunkLength.isOdd ? 1 : 0);
    }

    // 只接受本原型认识的 WAV 格式，不认识时明确报错，避免错误解码。
    if (dataOffset < 0 || channels < 1 || sampleRate < 1 ||
        !((format == 1 && <int>{8, 16, 24, 32}.contains(bitsPerSample)) ||
            (format == 3 && bitsPerSample == 32))) {
      throw const FormatException('Only PCM or 32-bit float WAV files are supported.');
    }
    final bytesPerSample = bitsPerSample ~/ 8;
    final frameCount = dataLength ~/ (bytesPerSample * channels);
    final samples = Float32List(frameCount);
    // 每个 frame 包含所有声道同一时刻的采样；这里将多声道取平均转单声道。
    for (var frame = 0; frame < frameCount; frame++) {
      var mono = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final sampleOffset = dataOffset +
            (frame * channels + channel) * bytesPerSample;
        double sample;
        if (format == 3) {
          sample = view.getFloat32(sampleOffset, Endian.little);
        } else {
          // WAV PCM 的 8-bit 是无符号数，其余位深是有符号整数。
          switch (bitsPerSample) {
            case 8:
              sample = (view.getUint8(sampleOffset) - 128) / 128;
              break;
            case 16:
              sample = view.getInt16(sampleOffset, Endian.little) / 32768;
              break;
            case 24:
              var value = view.getUint8(sampleOffset) |
                  (view.getUint8(sampleOffset + 1) << 8) |
                  (view.getUint8(sampleOffset + 2) << 16);
              if ((value & 0x800000) != 0) value |= 0xff000000;
              sample = value / 8388608;
              break;
            case 32:
              sample = view.getInt32(sampleOffset, Endian.little) / 2147483648;
              break;
            default:
              throw const FormatException('Unsupported WAV bit depth.');
          }
        }
        mono += sample;
      }
      samples[frame] = (mono / channels).clamp(-1.0, 1.0).toDouble();
    }
    return PcmWave(sampleRate: sampleRate, samples: samples);
  }
}

String _ascii(Uint8List data, int offset, int length) =>
    String.fromCharCodes(data.sublist(offset, offset + length));
