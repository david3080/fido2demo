import 'package:fido2demo/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanizeError', () {
    test('maps timeout', () {
      expect(humanizeError(Exception('TimeoutException after 30s')),
          contains('タイムアウト'));
    });

    test('maps network errors', () {
      expect(humanizeError(Exception('SocketException: failed')),
          contains('ネットワーク'));
      expect(humanizeError('Failed host lookup: oidc.sonrisa.co.jp'),
          contains('ネットワーク'));
    });

    test('maps cancellation (either case)', () {
      expect(humanizeError('user pressed cancel'), contains('キャンセル'));
      expect(humanizeError('Cancelled by user'), contains('キャンセル'));
    });

    test('strips leading "Exception: " for generic errors', () {
      expect(humanizeError(Exception('something broke')), 'something broke');
    });
  });
}
