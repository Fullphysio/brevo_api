import 'package:brevo_api/src/core/open_enum.dart';
import 'package:test/test.dart';

final class _Status extends BrevoOpenEnum {
  const _Status._(super.value, this.isKnown);

  static const _Status sent = _Status._('sent', true);
  static const _Status draft = _Status._('draft', true);
  static const List<_Status> values = [sent, draft];

  factory _Status.fromWire(String wire) {
    for (final value in values) {
      if (value.value == wire) {
        return value;
      }
    }
    return _Status._(wire, false);
  }

  @override
  final bool isKnown;
}

final class _Other extends BrevoOpenEnum {
  const _Other(super.value);

  @override
  bool get isKnown => true;
}

void main() {
  group('BrevoOpenEnum', () {
    test('a known wire value decodes to its constant', () {
      expect(_Status.fromWire('sent'), same(_Status.sent));
      expect(_Status.fromWire('sent').isKnown, isTrue);
    });

    test('an unknown wire value is preserved, not rejected', () {
      final unknown = _Status.fromWire('archived');
      expect(unknown.value, 'archived');
      expect(unknown.isKnown, isFalse);
    });

    test('equality is by type and wire value', () {
      expect(_Status.fromWire('archived'), _Status.fromWire('archived'));
      expect(_Status.fromWire('sent'), _Status.sent);
      expect(_Status.sent, isNot(equals(_Status.draft)));
      expect(_Status.sent, isNot(equals(const _Other('sent'))));
      expect(_Status.sent.hashCode, _Status.fromWire('sent').hashCode);
    });

    test('toString shows the type and the wire value', () {
      expect(_Status.sent.toString(), '_Status(sent)');
    });
  });
}
