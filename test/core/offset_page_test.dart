import 'package:brevo_api/src/core/offset_page.dart';
import 'package:test/test.dart';

void main() {
  BrevoOffsetPage<int> pageOf(
    List<int> items, {
    required int offset,
    int limit = 3,
    int? count,
    List<int>? offsets,
    List<int> all = const [0, 1, 2, 3, 4, 5, 6, 7],
  }) =>
      BrevoOffsetPage<int>(
        items: items,
        limit: limit,
        offset: offset,
        count: count,
        fetchPage: (next) async {
          offsets?.add(next);
          final slice = all.skip(next).take(limit).toList();
          return pageOf(
            slice,
            offset: next,
            limit: limit,
            count: count,
            offsets: offsets,
            all: all,
          );
        },
      );

  group('BrevoOffsetPage with a count', () {
    test('has a next page while items remain', () {
      expect(pageOf([0, 1, 2], offset: 0, count: 8).hasNextPage, isTrue);
      expect(pageOf([6, 7], offset: 6, count: 8).hasNextPage, isFalse);
      expect(pageOf([0, 1, 2], offset: 0, count: 3).hasNextPage, isFalse);
    });

    test('an empty page never has a next page', () {
      expect(pageOf(const [], offset: 0, count: 8).hasNextPage, isFalse);
    });

    test('nextPage advances the offset by the items received', () async {
      final offsets = <int>[];
      final next =
          await pageOf([0, 1, 2], offset: 0, count: 8, offsets: offsets)
              .nextPage();
      expect(offsets, [3]);
      expect(next.items, [3, 4, 5]);
      expect(next.offset, 3);
    });

    test('nextPage throws when there is no next page', () {
      expect(pageOf([6, 7], offset: 6, count: 8).nextPage, throwsStateError);
    });

    test('autoPaging walks every item across pages', () async {
      final offsets = <int>[];
      final items =
          await pageOf([0, 1, 2], offset: 0, count: 8, offsets: offsets)
              .autoPaging()
              .toList();
      expect(items, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(offsets, [3, 6]);
    });
  });

  group('BrevoOffsetPage without a count', () {
    test('is optimistic on a full page and stops on a short one', () {
      expect(pageOf([0, 1, 2], offset: 0).hasNextPage, isTrue);
      expect(pageOf([6, 7], offset: 6).hasNextPage, isFalse);
      expect(pageOf(const [], offset: 9).hasNextPage, isFalse);
    });

    test('autoPaging stops on the first short or empty page', () async {
      final offsets = <int>[];
      final items = await pageOf([0, 1, 2], offset: 0, offsets: offsets)
          .autoPaging()
          .toList();
      expect(items, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(offsets, [3, 6]);

      final exact = await pageOf([0, 1, 2],
          offset: 0,
          offsets: [],
          all: [0, 1, 2, 3, 4, 5]).autoPaging().toList();
      expect(exact, [0, 1, 2, 3, 4, 5]);
    });
  });
}
