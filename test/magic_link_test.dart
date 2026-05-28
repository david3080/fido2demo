import 'package:fido2demo/magic_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMagicLinkToken', () {
    test('extracts token from valid magic link', () {
      expect(
        parseMagicLinkToken(Uri.parse('https://oidc.sonrisa.co.jp/r?t=abc123')),
        'abc123',
      );
    });

    test('returns null for null uri', () {
      expect(parseMagicLinkToken(null), isNull);
    });

    test('rejects wrong host', () {
      expect(
        parseMagicLinkToken(Uri.parse('https://evil.example/r?t=abc')),
        isNull,
      );
    });

    test('rejects wrong path', () {
      expect(
        parseMagicLinkToken(Uri.parse('https://oidc.sonrisa.co.jp/other?t=abc')),
        isNull,
      );
    });

    test('rejects missing or empty token', () {
      expect(
        parseMagicLinkToken(Uri.parse('https://oidc.sonrisa.co.jp/r')),
        isNull,
      );
      expect(
        parseMagicLinkToken(Uri.parse('https://oidc.sonrisa.co.jp/r?t=')),
        isNull,
      );
    });

    test('accepts custom scheme jp.co.sonrisa.fido2demo://magic?t=…', () {
      expect(
        parseMagicLinkToken(Uri.parse('jp.co.sonrisa.fido2demo://magic?t=xyz789')),
        'xyz789',
      );
    });

    test('rejects custom scheme with wrong host', () {
      // OIDC コールバック等の他用途 URI は無視する
      expect(
        parseMagicLinkToken(Uri.parse('jp.co.sonrisa.fido2demo://callback?t=xyz')),
        isNull,
      );
    });

    test('rejects custom scheme with empty token', () {
      expect(
        parseMagicLinkToken(Uri.parse('jp.co.sonrisa.fido2demo://magic?t=')),
        isNull,
      );
    });
  });
}
