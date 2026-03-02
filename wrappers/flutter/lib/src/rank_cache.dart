/// Rank file downloading and caching.

import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'error.dart';
import 'registry.dart';

Future<Directory> cacheDir() async {
  final envDir = Platform.environment['TURBOTOKEN_CACHE_DIR'];
  if (envDir != null && envDir.isNotEmpty) {
    final dir = Directory(envDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  final appCache = await getApplicationCacheDirectory();
  final dir = Directory(p.join(appCache.path, 'turbotoken'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> ensureRankFile(String name) async {
  final spec = getEncodingSpec(name);
  final dir = await cacheDir();
  final file = File(p.join(dir.path, '$name.tiktoken'));

  if (await file.exists()) {
    return file;
  }

  final response = await http.get(Uri.parse(spec.rankFileUrl));
  if (response.statusCode != 200) {
    throw DownloadException(spec.rankFileUrl, statusCode: response.statusCode);
  }

  await file.writeAsBytes(response.bodyBytes);
  return file;
}

Future<Uint8List> readRankFile(String name) async {
  final file = await ensureRankFile(name);
  return file.readAsBytes();
}
