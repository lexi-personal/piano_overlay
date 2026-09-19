import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Raised when the platform cannot show a file dialog at all, rather than
/// when the user simply cancelled one.
class FileDialogUnavailable implements Exception {
  final String message;
  const FileDialogUnavailable(this.message);

  @override
  String toString() => message;
}

/// Thin wrapper around [FilePicker] that turns a missing platform dialog into
/// an error the UI can explain.
///
/// On Linux `file_picker` shells out to zenity, qarma or kdialog, and throws
/// if none of them is installed. That is a setup problem the user can fix, so
/// it deserves a real message instead of an unhandled exception.
class FileDialogs {
  FileDialogs._();

  static Future<String?> pickFile({
    required String dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    return _guard(() async {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: dialogTitle,
        type: allowedExtensions != null ? FileType.custom : type,
        allowedExtensions: allowedExtensions,
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.single.path;
    });
  }

  static Future<String?> pickDirectory({required String dialogTitle}) {
    return _guard(
        () => FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle));
  }

  static Future<String?> saveFile({
    required String dialogTitle,
    String? fileName,
    List<String>? allowedExtensions,
  }) {
    return _guard(() => FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          type: allowedExtensions == null ? FileType.any : FileType.custom,
          allowedExtensions: allowedExtensions,
        ));
  }

  @visibleForTesting
  static Future<String?> guard(Future<String?> Function() action) =>
      _guard(action);

  static Future<String?> _guard(Future<String?> Function() action) async {
    try {
      return await action();
    } on Exception catch (e) {
      if (_isMissingDialogBackend(e)) {
        throw FileDialogUnavailable(_installHint());
      }
      rethrow;
    }
  }

  /// file_picker reports a missing helper as a plain Exception naming the
  /// executable it looked for, so the message is all we have to match on.
  static bool _isMissingDialogBackend(Exception e) {
    final message = e.toString();
    return message.contains("Couldn't find the executable") ||
        message.contains('Couldn\'t find the executable');
  }

  static String _installHint() {
    if (Platform.isLinux) {
      return 'File dialogs need zenity, which is not installed. '
          'Install it with "sudo apt install zenity" '
          '(or "sudo dnf install zenity") and try again.';
    }
    return 'This system has no file dialog available.';
  }
}
