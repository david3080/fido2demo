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

  group('explainRegistrationHttpError', () {
    test('400 "invalid or expired token" → 期限切れの親切メッセージ', () {
      final m = explainRegistrationHttpError(400, 'invalid or expired token');
      expect(m, contains('有効期限'));
      expect(m, contains('30分'));
      expect(m, contains('メール'));
    });

    test('400 "challenge invalid/expired" も期限切れ扱い', () {
      final m = explainRegistrationHttpError(400, 'challenge invalid/expired');
      expect(m, contains('有効期限'));
    });

    test('401 も期限切れ扱い', () {
      final m = explainRegistrationHttpError(401, '');
      expect(m, contains('有効期限'));
    });

    test('409 は「既に登録済み」', () {
      final m = explainRegistrationHttpError(409, 'already registered');
      expect(m, contains('既に登録済み'));
    });

    test('5xx はサーバ一時障害', () {
      final m = explainRegistrationHttpError(503, 'down');
      expect(m, contains('一時的に利用できません'));
    });

    test('400 その他は本文を含めて表示', () {
      final m = explainRegistrationHttpError(400, 'something else');
      expect(m, contains('something else'));
      expect(m, isNot(contains('有効期限')));
    });

    test('未知ステータスは HTTP コードを含める', () {
      final m = explainRegistrationHttpError(418, 'teapot');
      expect(m, contains('418'));
    });
  });
}
