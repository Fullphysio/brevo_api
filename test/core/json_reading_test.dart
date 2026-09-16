import 'package:brevo_api/src/core/decode_exception.dart';
import 'package:brevo_api/src/core/json_reading.dart';
import 'package:test/test.dart';

void main() {
  final json = <String, Object?>{
    'string': 's',
    'int': 1,
    'wholeDouble': 2.0,
    'double': 2.5,
    'bool': true,
    'null': null,
    'object': {'k': 'v'},
    'list': [1, 'a', null, true, 3.0, 4.5],
    'objects': [
      {'id': 1},
      {'id': 2},
    ],
    'strings': ['a', 1, 'b'],
    'stringMap': {'a': 'x', 'b': 2, 'c': null},
    'dateTime': '2024-01-15T10:30:00.000Z',
    'date': '2024-01-15',
    'badDate': 'yesterday',
  };

  group('optional readers', () {
    test('return null or empty for absent keys', () {
      expect(json.optString('missing'), isNull);
      expect(json.optInt('missing'), isNull);
      expect(json.optDouble('missing'), isNull);
      expect(json.optBool('missing'), isNull);
      expect(json.optDateTime('missing'), isNull);
      expect(json.optObject('missing'), isNull);
      expect(json.optNested('missing', (o) => o), isNull);
      expect(json.optList('missing', (e) => e), isEmpty);
      expect(json.optObjectList('missing', (o) => o, objectName: 'T'), isEmpty);
      expect(json.optStringList('missing'), isEmpty);
      expect(json.optIntList('missing'), isEmpty);
      expect(json.optDoubleList('missing'), isEmpty);
      expect(json.optBoolList('missing'), isEmpty);
      expect(json.optObjectMap('missing'), isEmpty);
      expect(json.optStringMap('missing'), isEmpty);
      expect(json.optEnum('missing', (w) => w), isNull);
    });

    test('return null for a null value or a wrong type', () {
      expect(json.optString('null'), isNull);
      expect(json.optString('int'), isNull);
      expect(json.optInt('string'), isNull);
      expect(json.optInt('double'), isNull);
      expect(json.optBool('int'), isNull);
      expect(json.optObject('list'), isNull);
      expect(json.optList('object', (e) => e), isEmpty);
    });

    test('read scalars, widening numbers like JSON does', () {
      expect(json.optString('string'), 's');
      expect(json.optInt('int'), 1);
      expect(json.optInt('wholeDouble'), 2);
      expect(json.optDouble('int'), 1.0);
      expect(json.optDouble('double'), 2.5);
      expect(json.optBool('bool'), isTrue);
    });

    test('parse ISO instants and plain dates, never throwing', () {
      expect(json.optDateTime('dateTime'), DateTime.utc(2024, 1, 15, 10, 30));
      expect(json.optDateTime('date'), DateTime(2024, 1, 15));
      expect(json.optDateTime('badDate'), isNull);
      expect(json.optDateTime('int'), isNull);
    });

    test('read nested objects and lists', () {
      expect(json.optObject('object'), {'k': 'v'});
      expect(json.optNested('object', (o) => o['k']), 'v');
      expect(json.optList('list', (e) => e), [1, 'a', null, true, 3.0, 4.5]);
      expect(
        json.optObjectList('objects', (o) => o['id'], objectName: 'T'),
        [1, 2],
      );
      expect(json.optStringList('strings'), ['a', 'b']);
      expect(json.optIntList('list'), [1, 3]);
      expect(json.optDoubleList('list'), [1.0, 3.0, 4.5]);
      expect(json.optBoolList('list'), [true]);
    });

    test('read maps, keeping or stringifying values', () {
      expect(json.optObjectMap('stringMap'), {'a': 'x', 'b': 2, 'c': null});
      expect(json.optStringMap('stringMap'), {'a': 'x', 'b': '2'});
      expect(() => json.optObjectMap('stringMap')['z'] = 1,
          throwsUnsupportedError);
    });

    test('an object list with a non-object element is a decode failure', () {
      expect(
        () => json.optObjectList('list', (o) => o, objectName: 'Thing'),
        throwsA(
          isA<BrevoDecodeException>().having(
            (e) => e.message,
            'message',
            contains('Thing: key "list[]"'),
          ),
        ),
      );
    });

    test('optEnum maps through the decoder', () {
      expect(json.optEnum('string', (w) => w.toUpperCase()), 'S');
    });
  });

  group('required readers', () {
    test('return the value when present', () {
      expect(json.requireString('string', 'T'), 's');
      expect(json.requireInt('int', 'T'), 1);
      expect(json.requireInt('wholeDouble', 'T'), 2);
      expect(json.requireObject('object', 'T'), {'k': 'v'});
    });

    test('throw naming the object and key when missing', () {
      expect(
        () => json.requireString('missing', 'Contact'),
        throwsA(
          isA<BrevoDecodeException>().having(
            (e) => e.message,
            'message',
            'Contact: required key "missing" is missing or null',
          ),
        ),
      );
      expect(() => json.requireInt('null', 'Contact'),
          throwsA(isA<BrevoDecodeException>()));
      expect(() => json.requireObject('missing', 'Contact'),
          throwsA(isA<BrevoDecodeException>()));
    });

    test('throw naming the type when the value has the wrong type', () {
      expect(
        () => json.requireString('int', 'Contact'),
        throwsA(
          isA<BrevoDecodeException>().having(
            (e) => e.message,
            'message',
            contains('unexpected type (int)'),
          ),
        ),
      );
      expect(() => json.requireInt('double', 'Contact'),
          throwsA(isA<BrevoDecodeException>()));
      expect(() => json.requireObject('list', 'Contact'),
          throwsA(isA<BrevoDecodeException>()));
    });
  });

  group('brevoRequireJsonObject', () {
    test('passes an object through', () {
      expect(brevoRequireJsonObject({'a': 1}, objectName: 'T'), {'a': 1});
    });

    test('rejects anything else with a message naming the type', () {
      expect(
        () => brevoRequireJsonObject([1], objectName: 'Contact'),
        throwsA(
          isA<BrevoDecodeException>().having(
            (e) => e.toString(),
            'toString',
            'BrevoDecodeException: Contact: expected a JSON object but got '
                'List<int>: [1]',
          ),
        ),
      );
    });

    test('truncates a long value in the description', () {
      final long = 'x' * 500;
      expect(
        () => brevoRequireJsonObject(long, objectName: 'T'),
        throwsA(
          isA<BrevoDecodeException>().having(
            (e) => e.message.length,
            'length',
            lessThan(300),
          ),
        ),
      );
    });
  });
}
