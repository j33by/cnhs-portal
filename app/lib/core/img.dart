import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Pictures saved on the phone. A picture is downloaded once and then shown from the saved copy (instantly, also with no
/// internet). Every upload gets its own web address (profile_<time>.jpg), so a new photo is a new address: it is downloaded and
/// shown the moment the live data brings the new address, while the old saved copy is simply not used any more.
class ImgCache {
  /// The last picture problem (shown on the Profile screen so a failure is never silent).
  static final lastError = ValueNotifier<String?>(null);
  static Directory? _dir;
  static Future<Directory> _d() async {
    if (_dir != null) { return _dir!; }
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}img_cache');
    if (!await d.exists()) { await d.create(recursive: true); }
    return _dir = d;
  }
  static String _name(String url) {            // stable file name for an address (two 32-bit FNV-1a hashes)
    var a = 0x811c9dc5, b = 0x01000193;
    for (final c in url.codeUnits) { a = ((a ^ c) * 0x01000193) & 0xFFFFFFFF; b = ((b ^ c) * 0x811c9dc5) & 0xFFFFFFFF; }
    return '${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}${url.length.toRadixString(16)}';
  }
  static Future<File> _f(String url) async => File('${(await _d()).path}${Platform.pathSeparator}${_name(url)}');
  static Future<Uint8List?> read(String url) async {
    try { final f = await _f(url); if (await f.exists()) { final b = await f.readAsBytes(); if (b.isNotEmpty) { return b; } } } catch (_) {}
    return null;
  }
  static Future<void> write(String url, Uint8List bytes) async {
    try { final f = await _f(url); final t = File('${f.path}.tmp'); await t.writeAsBytes(bytes, flush: true); await t.rename(f.path); } catch (_) {}
  }
  static Future<void> drop(String url) async { try { final f = await _f(url); if (await f.exists()) { await f.delete(); } } catch (_) {} }
  static Future<void> wipe() async {
    try { final d = await _d(); if (await d.exists()) { await d.delete(recursive: true); } _dir = null; } catch (_) {}
  }
}

/// Drop-in replacement for NetworkImage: saved copy first, otherwise download, save, show.
class CachedNetImage extends ImageProvider<CachedNetImage> {
  const CachedNetImage(this.url);
  final String url;
  @override
  Future<CachedNetImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<CachedNetImage>(this);
  @override
  ImageStreamCompleter loadImage(CachedNetImage key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    final saved = await ImgCache.read(url);
    if (saved != null) {
      try { return ImageInfo(image: await decodeImageFromList(saved)); } catch (_) { await ImgCache.drop(url); }   // damaged copy: download again
    }
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) { throw HttpException('HTTP ${r.statusCode}, ${r.bodyBytes.length} bytes, type ${r.headers['content-type']}'); }
      final img = await decodeImageFromList(r.bodyBytes);
      unawaited(ImgCache.write(url, r.bodyBytes));
      return ImageInfo(image: img);
    } catch (e) {
      ImgCache.lastError.value = '$e  [${Uri.parse(url).host}]';
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is CachedNetImage && other.url == url;
  @override
  int get hashCode => url.hashCode;
}
