import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart';

/// Records 16 kHz mono PCM16 into a WAV file for whisper.cpp transcription.
///
/// * Android: native `AudioRecord` through the `chatvv/mic` method channel.
/// * Linux: `arecord` (alsa-utils) so the same push-to-talk works on desktop.
/// * Other desktop platforms: not implemented yet (throws a readable error).
class MicRecorder {
  static const MethodChannel _channel = MethodChannel('chatvv/mic');

  Future<File>? _tempFile;
  Process? _process;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<void> start() async {
    if (_recording) return;
    if (Platform.isAndroid) {
      final ok = await _channel.invokeMethod<bool>('start') ?? false;
      if (!ok) {
        throw PlatformException(
          code: 'mic_start_failed',
          message: '无法打开麦克风',
        );
      }
    } else if (Platform.isLinux) {
      final support = await appSupportDirectory();
      final dir = Directory('${support.path}/recordings');
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}/mic_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      final process = await Process.start('arecord', [
        '-q',
        '-f',
        'S16_LE',
        '-r',
        '16000',
        '-c',
        '1',
        '-t',
        'wav',
        file.path,
      ]);
      _process = process;
      _tempFile = Future.value(file);
    } else {
      throw PlatformException(
        code: 'mic_unsupported',
        message: '当前平台暂不支持录音（Linux 可用 arecord）',
      );
    }
    _recording = true;
  }

  /// Normalized RMS of the most recent audio chunk (0..1). Android only; other
  /// platforms return 0 (push-to-talk does not need it).
  Future<double> level() async {
    if (!_recording) return 0;
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod<double>('level') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('stop');
    }
    final process = _process;
    _process = null;
    final file = await _tempFile;
    _tempFile = null;
    if (process != null) {
      process.kill(ProcessSignal.sigint);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
    }
    if (file == null || !await file.exists()) return null;
    if (await file.length() < 1000) return null;
    return file.path;
  }

  Future<void> cancel() async {
    if (!_recording) return;
    _recording = false;
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('cancel');
      } catch (_) {}
      return;
    }
    final process = _process;
    _process = null;
    final file = await _tempFile;
    _tempFile = null;
    if (process != null) {
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } catch (_) {}
    }
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
}
