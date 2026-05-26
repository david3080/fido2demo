import 'package:fido2demo/ciba_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingApproval.fromFcmData', () {
    test('parses a full ciba_request', () {
      final p = PendingApproval.fromFcmData({
        'type': 'ciba_request',
        'auth_req_id': 'req-1',
        'client_name': 'Demo RP',
        'scope': 'openid profile',
        'binding_message': '1234',
      });
      expect(p, isNotNull);
      expect(p!.authReqId, 'req-1');
      expect(p.clientName, 'Demo RP');
      expect(p.scope, 'openid profile');
      expect(p.bindingMessage, '1234');
    });

    test('defaults optional fields when absent', () {
      final p = PendingApproval.fromFcmData({
        'type': 'ciba_request',
        'auth_req_id': 'req-2',
      });
      expect(p, isNotNull);
      expect(p!.clientName, '?');
      expect(p.scope, '');
      expect(p.bindingMessage, '');
    });

    test('returns null for wrong type', () {
      expect(
        PendingApproval.fromFcmData({'type': 'remote_cursor', 'auth_req_id': 'x'}),
        isNull,
      );
    });

    test('returns null when auth_req_id missing', () {
      expect(PendingApproval.fromFcmData({'type': 'ciba_request'}), isNull);
    });
  });
}
