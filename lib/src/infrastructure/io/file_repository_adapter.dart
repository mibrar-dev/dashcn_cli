import 'dart:io';

import 'package:dashcn_cli/src/domain/repositories/file_repository.dart';

class FileRepositoryAdapter implements FileRepository {
  const FileRepositoryAdapter();

  @override
  Future<bool> exists(String path) async {
    return File(path).exists();
  }

  @override
  Future<void> write(String path, String contents) async {
    final file = File(path);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    await file.writeAsString(contents);
  }
}
