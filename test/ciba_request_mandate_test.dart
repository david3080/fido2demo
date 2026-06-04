import 'dart:convert';

import 'package:fido2demo/ciba_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingApproval.fromFcmData - authorization_details', () {
    test('FCM data の JSON 文字列を List<Map> に parse する', () {
      final ad = [
        {'type': 'points', 'amount': '500', 'program': 'リーサ', 'merchant': 'X'}
      ];
      final p = PendingApproval.fromFcmData({
        'type': 'ciba_request',
        'auth_req_id': 'AR1',
        'client_name': 'agent',
        'scope': 'openid',
        'binding_message': '500 PT 使用',
        'authorization_details': jsonEncode(ad),
      });
      expect(p, isNotNull);
      expect(p!.authorizationDetails, hasLength(1));
      expect(p.authorizationDetails!.first['type'], 'points');
      expect(p.authorizationDetails!.first['program'], 'リーサ');
    });

    test('authorization_details が無ければ null', () {
      final p = PendingApproval.fromFcmData({
        'type': 'ciba_request',
        'auth_req_id': 'AR1',
        'binding_message': 'login',
      });
      expect(p!.authorizationDetails, isNull);
    });

    test('壊れた JSON は null にして binding_message にフォールバック', () {
      final p = PendingApproval.fromFcmData({
        'type': 'ciba_request',
        'auth_req_id': 'AR1',
        'binding_message': 'login',
        'authorization_details': '{this is not json',
      });
      expect(p!.authorizationDetails, isNull);
      expect(p.bindingMessage, 'login');
    });

    test('JSON が配列でなければ null（型を厳しく）', () {
      final p = PendingApproval.fromFcmData({
        'type': 'ciba_request',
        'auth_req_id': 'AR1',
        'authorization_details': '{"type":"points"}',
      });
      expect(p!.authorizationDetails, isNull);
    });

    test('type が ciba_request でなければ生成しない', () {
      final p = PendingApproval.fromFcmData({'type': 'other_event'});
      expect(p, isNull);
    });

    test('auth_req_id が無ければ生成しない', () {
      final p = PendingApproval.fromFcmData({'type': 'ciba_request'});
      expect(p, isNull);
    });
  });
}
