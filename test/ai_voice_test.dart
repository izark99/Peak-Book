import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peak_book/ai_voice.dart';

void main() {
  test('unpackVoice moves the folder with tokens.txt into place', () async {
    final dir = await Directory.systemTemp.createTemp('voice');
    addTearDown(() => dir.delete(recursive: true));
    final tar = Archive();
    for (final name in ['${AiVoice.voice}.onnx', 'tokens.txt', 'espeak-ng-data/vi_dict']) {
      tar.add(ArchiveFile.bytes('vits-piper-${AiVoice.voice}/$name', utf8.encode('x')));
    }
    final archive = File(p.join(dir.path, 'v.tar.bz2'))
      ..writeAsBytesSync(BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(tar)));
    final dest = p.join(dir.path, 'voices', AiVoice.voice);

    await AiVoice.unpackVoice(archive.path, dest);
    expect(AiVoice.isVoiceDir(dest), isTrue);
    expect(File(p.join(dest, 'espeak-ng-data', 'vi_dict')).existsSync(), isTrue);
    expect(Directory('$dest.tmp').existsSync(), isFalse);
  });

  test('useAiVoice only for Vietnamese when enabled and installed', () {
    expect(useAiVoice(enabled: true, installed: true, lang: 'vi'), isTrue);
    expect(useAiVoice(enabled: true, installed: true, lang: 'zh'), isFalse);
    expect(useAiVoice(enabled: true, installed: false, lang: 'vi'), isFalse);
    expect(useAiVoice(enabled: false, installed: true, lang: 'vi'), isFalse);
  });

  test('speedFor maps flutter_tts rate to sherpa speed', () {
    expect(AiVoice.speedFor(0.5), 1.0);
    expect(AiVoice.speedFor(0.1), 0.5);
    expect(AiVoice.speedFor(1.0), 2.0);
  });
}
