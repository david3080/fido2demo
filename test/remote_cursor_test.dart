import 'package:fido2demo/remote_cursor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const targets = {'name', 'save', 'logout'};

  group('parseRemoteCursorEvent', () {
    test('shows cursor for a valid target', () {
      final ev = parseRemoteCursorEvent(
        {'type': 'remote_cursor', 'target': 'save', 'label': 'ここを押す'},
        targets,
      );
      expect(ev, isA<CursorShow>());
      final cmd = (ev as CursorShow).command;
      expect(cmd.target, 'save');
      expect(cmd.label, 'ここを押す');
    });

    test('defaults label to empty', () {
      final ev = parseRemoteCursorEvent(
        {'type': 'remote_cursor', 'target': 'name'},
        targets,
      );
      expect((ev as CursorShow).command.label, '');
    });

    test('target none clears', () {
      final ev = parseRemoteCursorEvent(
        {'type': 'remote_cursor', 'target': 'none'},
        targets,
      );
      expect(ev, isA<CursorClear>());
    });

    test('ignores wrong type', () {
      expect(
        parseRemoteCursorEvent({'type': 'ciba_request', 'target': 'save'}, targets),
        isA<CursorIgnore>(),
      );
    });

    test('ignores unknown or missing target', () {
      expect(
        parseRemoteCursorEvent({'type': 'remote_cursor', 'target': 'bogus'}, targets),
        isA<CursorIgnore>(),
      );
      expect(
        parseRemoteCursorEvent({'type': 'remote_cursor'}, targets),
        isA<CursorIgnore>(),
      );
    });
  });
}
