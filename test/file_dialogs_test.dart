import 'package:flutter_test/flutter_test.dart';
import 'package:piano_overlay/services/file_dialogs.dart';

void main() {
  group('file dialogs', () {
    test('a picked path is passed straight through', () async {
      expect(await FileDialogs.guard(() async => '/tmp/song.mid'),
          '/tmp/song.mid');
    });

    test('a cancelled dialog stays null', () async {
      expect(await FileDialogs.guard(() async => null), isNull);
    });

    test('a missing system dialog becomes an actionable message', () async {
      // The exact wording file_picker throws when no helper is installed.
      Future<String?> missingHelper() async =>
          throw Exception("Couldn't find the executable zenity in the path.");

      await expectLater(
        FileDialogs.guard(missingHelper),
        throwsA(isA<FileDialogUnavailable>()
            .having((e) => e.message, 'message', contains('zenity'))
            .having((e) => e.message, 'message', contains('install'))),
      );
    });

    test('unrelated failures are not disguised', () async {
      Future<String?> otherFailure() async =>
          throw Exception('disk on fire');

      await expectLater(
        FileDialogs.guard(otherFailure),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('disk on fire'))),
      );
      Object? caught;
      try {
        await FileDialogs.guard(otherFailure);
      } catch (e) {
        caught = e;
      }
      expect(caught, isNot(isA<FileDialogUnavailable>()));
    });
  });
}
