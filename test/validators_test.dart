import 'package:fido2demo/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidEmail', () {
    test('accepts typical addresses', () {
      expect(isValidEmail('a@example.com'), isTrue);
      expect(isValidEmail('user.name+tag@sub.example.co.jp'), isTrue);
    });

    test('rejects missing @ / domain / dot', () {
      expect(isValidEmail('plainstring'), isFalse);
      expect(isValidEmail('no-at-sign.com'), isFalse);
      expect(isValidEmail('a@b'), isFalse); // ドット無し
      expect(isValidEmail('@example.com'), isFalse);
      expect(isValidEmail('a@.com'), isFalse);
    });

    test('rejects whitespace', () {
      expect(isValidEmail('a b@example.com'), isFalse);
      expect(isValidEmail(' a@example.com'), isFalse);
    });

    test('rejects empty and over-length (>254)', () {
      expect(isValidEmail(''), isFalse);
      final long = '${'a' * 250}@e.com'; // 256 文字
      expect(long.length > 254, isTrue);
      expect(isValidEmail(long), isFalse);
    });
  });
}
