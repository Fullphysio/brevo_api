import 'package:brevo_api/src/core/path_encoding.dart';
import 'package:test/test.dart';

void main() {
  group('brevoPathSegment', () {
    test('leaves safe characters alone', () {
      expect(brevoPathSegment("abc-XYZ_0.9!~*'()"), "abc-XYZ_0.9!~*'()");
    });

    test('encodes everything encodeURIComponent encodes', () {
      expect(
        brevoPathSegment('jo hn+x@ex.com/ü?#%'),
        'jo%20hn%2Bx%40ex.com%2F%C3%BC%3F%23%25',
      );
    });

    test('stringifies an integer identifier', () {
      expect(brevoPathSegment(12), '12');
    });

    test('rejects an empty segment and dot segments', () {
      expect(() => brevoPathSegment(''), throwsArgumentError);
      expect(() => brevoPathSegment('.'), throwsArgumentError);
      expect(() => brevoPathSegment('..'), throwsArgumentError);
    });

    test('rejects a value that is neither a string nor a number', () {
      expect(() => brevoPathSegment(DateTime(2026)), throwsArgumentError);
      expect(() => brevoPathSegment(['1']), throwsArgumentError);
      expect(() => brevoPathSegment({'id': 1}), throwsArgumentError);
    });
  });
}
