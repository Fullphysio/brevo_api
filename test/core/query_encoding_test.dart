import 'package:brevo_api/src/core/query_encoding.dart';
import 'package:test/test.dart';

void main() {
  group('brevoQueryEncode', () {
    test('a null value is dropped entirely', () {
      expect(brevoQueryEncode({'a': null, 'b': 1}), 'b=1');
    });

    test('a list repeats the bare key per element', () {
      expect(
          brevoQueryEncode({
            'ids': [1, 2, 3]
          }),
          'ids=1&ids=2&ids=3');
    });

    test('null elements of a list are skipped', () {
      expect(
          brevoQueryEncode({
            'ids': [1, null, 3]
          }),
          'ids=1&ids=3');
    });

    test('an empty list or map contributes nothing', () {
      expect(
          brevoQueryEncode(
              {'a': <Object?>[], 'b': <String, Object?>{}, 'c': 1}),
          'c=1');
    });

    test('a nested map uses bracket keys', () {
      expect(
        brevoQueryEncode({
          'a': {'b': 'c', 'd': 1},
        }),
        'a%5Bb%5D=c&a%5Bd%5D=1',
      );
    });

    test('a map inside a list repeats the bare key', () {
      expect(
        brevoQueryEncode({
          'f': [
            {'x': 1},
            {'y': 2},
          ],
        }),
        'f%5Bx%5D=1&f%5By%5D=2',
      );
    });

    test('booleans and numbers use their JS String() form', () {
      expect(
        brevoQueryEncode({'a': true, 'b': false, 'c': 2.0, 'd': 2.5, 'e': -1}),
        'a=true&b=false&c=2&d=2.5&e=-1',
      );
    });

    test('a DateTime is written as an ISO-8601 UTC instant', () {
      expect(
        brevoQueryEncode({'since': DateTime.utc(2024, 1, 15, 10, 30, 0, 7)}),
        'since=2024-01-15T10%3A30%3A00.007Z',
      );
      expect(
        brevoQueryEncode({'since': DateTime(2024, 1, 15, 10, 30).toUtc()}),
        startsWith('since=2024-01-15T'),
      );
    });

    test('pairs keep insertion order', () {
      expect(brevoQueryEncode({'z': 1, 'a': 2}), 'z=1&a=2');
    });
  });

  group('brevoUriComponentEncode', () {
    test('matches encodeURIComponent for the unreserved and reserved sets', () {
      expect(brevoUriComponentEncode("AZaz09-_.!~*'()"), "AZaz09-_.!~*'()");
      expect(brevoUriComponentEncode(' &=+/?#[]@:;,\$%'),
          '%20%26%3D%2B%2F%3F%23%5B%5D%40%3A%3B%2C%24%25');
    });

    test('encodes non-ASCII from UTF-8 bytes', () {
      expect(brevoUriComponentEncode('é/ü'), '%C3%A9%2F%C3%BC');
      expect(brevoUriComponentEncode('日本'), '%E6%97%A5%E6%9C%AC');
    });
  });
}
