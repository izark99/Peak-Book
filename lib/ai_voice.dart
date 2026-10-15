import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Offline Vietnamese neural voice (Piper via sherpa-onnx). Downloaded on first use, ~67MB.
class AiVoice {
  static const voice = 'vi_VN-vais1000-medium';
  static const url = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-$voice.tar.bz2';

  static Future<Directory> _dir() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'voices', voice));

  static bool isVoiceDir(String dir) =>
      File(p.join(dir, '$voice.onnx')).existsSync() && File(p.join(dir, 'tokens.txt')).existsSync();

  static Future<bool> installed() async => isVoiceDir((await _dir()).path);

  static Future<void> uninstall() async {
    await stop();
    final d = await _dir();
    if (d.existsSync()) await d.delete(recursive: true);
  }

  /// Downloads and unpacks the voice. [onProgress] gets 0..1 while downloading.
  static Future<void> install(void Function(double) onProgress) async {
    final dest = await _dir();
    await dest.parent.create(recursive: true);
    final archive = File(p.join(dest.parent.path, '$voice.tar.bz2'));
    try {
      final res = await http.Client().send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = archive.openWrite();
      await res.stream.map((chunk) {
        got += chunk.length;
        if (total > 0) onProgress(got / total);
        return chunk;
      }).pipe(sink);
      final path = archive.path, destPath = dest.path;
      await Isolate.run(() => unpackVoice(path, destPath));
    } finally {
      if (archive.existsSync()) await archive.delete();
    }
  }

  /// Extracts a sherpa-onnx voice .tar.bz2 and moves the folder holding tokens.txt to [dest].
  static Future<void> unpackVoice(String archive, String dest) async {
    final tmp = Directory('$dest.tmp');
    if (tmp.existsSync()) await tmp.delete(recursive: true);
    try {
      await extractFileToDisk(archive, tmp.path);
      final tokens = tmp.listSync(recursive: true).whereType<File>().firstWhere(
          (f) => p.basename(f.path) == 'tokens.txt',
          orElse: () => throw const FormatException('Gói giọng thiếu tokens.txt'));
      if (Directory(dest).existsSync()) await Directory(dest).delete(recursive: true);
      await tokens.parent.rename(dest);
    } finally {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    }
  }

  // --- Playback: one long-lived isolate keeps the model loaded; WAVs are rendered one paragraph ahead.

  static SendPort? _worker;
  static final _pending = <int, Completer<String>>{};
  static final _rendered = <String, Future<String>>{};
  static final _player = AudioPlayer();
  static Completer<void>? _playing;
  static int _seq = 0;

  static Future<SendPort> _start() async {
    if (_worker != null) return _worker!;
    final dir = (await _dir()).path, tmp = (await getTemporaryDirectory()).path;
    final inbox = ReceivePort();
    await Isolate.spawn(_workerMain, (inbox.sendPort, dir, tmp));
    final ready = Completer<SendPort>();
    inbox.listen((m) {
      if (m is SendPort) return ready.complete(m);
      final (int id, String? path, String? error) = m as (int, String?, String?);
      final c = _pending.remove(id);
      error == null ? c?.complete(path!) : c?.completeError(Exception(error));
    });
    return _worker = await ready.future;
  }

  static void _workerMain((SendPort, String, String) args) {
    final (reply, dir, tmp) = args;
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    so.OfflineTts? tts;
    String? loadError;
    try {
      so.initBindings();
      tts = so.OfflineTts(so.OfflineTtsConfig(
        model: so.OfflineTtsModelConfig(
          vits: so.OfflineTtsVitsModelConfig(
            model: p.join(dir, '$voice.onnx'),
            tokens: p.join(dir, 'tokens.txt'),
            dataDir: p.join(dir, 'espeak-ng-data'),
          ),
          numThreads: 2,
          debug: false,
        ),
      ));
    } catch (e) {
      loadError = 'Không tải được giọng AI: $e';
    }
    inbox.listen((m) {
      final (int id, String text, double speed) = m as (int, String, double);
      if (tts == null) return reply.send((id, null, loadError));
      try {
        final audio = tts.generate(text: text, speed: speed);
        final out = p.join(tmp, 'peak_tts_$id.wav');
        so.writeWave(filename: out, samples: audio.samples, sampleRate: audio.sampleRate);
        reply.send((id, out, null));
      } catch (e) {
        reply.send((id, null, '$e'));
      }
    });
  }

  static Future<String> _render(String text, double speed) => _rendered.putIfAbsent(text, () async {
        final worker = await _start();
        final id = ++_seq;
        final c = _pending[id] = Completer<String>();
        worker.send((id, text, speed));
        return c.future;
      });

  /// flutter_tts rate (0.1..1, 0.5 = normal) to sherpa speed (1.0 = normal).
  static double speedFor(double rate) => (rate * 2).clamp(0.5, 2.0);

  /// Speaks [text] and returns when playback ends or [stop] is called; renders [next] meanwhile.
  static Future<void> speak(String text, double rate, {String? next}) async {
    final speed = speedFor(rate);
    final wav = await _render(text, speed);
    if (next != null) _render(next, speed).ignore();
    final playing = _playing = Completer<void>();
    final sub = _player.onPlayerComplete.listen((_) {
      if (!playing.isCompleted) playing.complete();
    });
    try {
      await _player.play(DeviceFileSource(wav));
      await playing.future;
    } finally {
      await sub.cancel();
      _rendered.remove(text);
      File(wav).delete().ignore();
    }
  }

  static Future<void> stop() async {
    await _player.stop();
    if (_playing?.isCompleted == false) _playing!.complete();
    _rendered.clear();
  }
}

/// AI voice only reads Vietnamese; everything else stays on the system voice.
bool useAiVoice({required bool enabled, required bool installed, required String lang}) =>
    enabled && installed && lang.toLowerCase().startsWith('vi');
