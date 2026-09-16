/// Fetches the page starting at [offset], re-running the same list call the
/// current page came from with an updated `offset` parameter.
typedef BrevoOffsetPageFetcher<T> = Future<BrevoOffsetPage<T>> Function(
  int offset,
);

/// One page of a Brevo list endpoint paginated with `limit` / `offset`.
///
/// Brevo has no cursor pagination: every list takes a `limit` and an
/// `offset`, and most answer with a `count` of matching records alongside
/// the page. `@getbrevo/brevo` offers no pagination helper, so this class is
/// this package's own convenience — generated `*Paged` methods construct it
/// and hand back a fetcher for the next page. Iterate everything with
/// [autoPaging].
final class BrevoOffsetPage<T> {
  /// Creates a page holding [items] that was requested with [limit] and
  /// [offset].
  ///
  /// [count] is the total the server reported, or `null` for a list that
  /// reports none, in which case [hasNextPage] is optimistic: a full page
  /// may be followed by more.
  const BrevoOffsetPage({
    required this.items,
    required this.limit,
    required this.offset,
    required this.count,
    required BrevoOffsetPageFetcher<T> fetchPage,
  }) : _fetchPage = fetchPage;

  /// The items this page carried.
  final List<T> items;

  /// The page size the request asked for.
  final int limit;

  /// The index of the first item of this page within the whole list.
  final int offset;

  /// The total number of matching records across all pages, when the server
  /// reported one.
  final int? count;

  final BrevoOffsetPageFetcher<T> _fetchPage;

  /// Whether asking for [nextPage] makes sense.
  ///
  /// With a [count], `true` while items remain beyond this page. Without one,
  /// `true` for a full page — as with any optimistic scheme, the following
  /// page may come back empty.
  bool get hasNextPage {
    if (items.isEmpty) {
      return false;
    }
    final total = count;
    return total == null
        ? items.length >= limit
        : offset + items.length < total;
  }

  /// Fetches the following page. Throws a [StateError] when [hasNextPage] is
  /// `false`.
  Future<BrevoOffsetPage<T>> nextPage() {
    if (!hasNextPage) {
      throw StateError(
        'No next page expected; please check `hasNextPage` before calling '
        '`nextPage()`.',
      );
    }
    return _fetchPage(offset + items.length);
  }

  /// Lazily walks every item across every page, fetching each next page only
  /// once the current one is exhausted.
  Stream<T> autoPaging() async* {
    BrevoOffsetPage<T> page = this;
    while (true) {
      for (final item in page.items) {
        yield item;
      }
      if (!page.hasNextPage) {
        return;
      }
      page = await page.nextPage();
    }
  }
}
