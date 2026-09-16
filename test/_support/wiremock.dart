import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// Reads back the request WireMock received last and asserts it is the one
/// the call under test was meant to send.
///
/// Brevo's own mappings match on the path template and, for twelve of the
/// 291 operations, on a handful of query parameters. WireMock answers
/// anything else with a 404, so a wrong path already fails the call — but a
/// query parameter the generator dropped, misspelled or invented sails
/// through unnoticed on the other 279. Comparing against the server's
/// request journal closes that gap: [method] and [path] must match exactly,
/// and the query string must carry exactly [queryKeys], no more and no less.
Future<void> expectLastRequest(
  String host, {
  required String method,
  required String path,
  required Set<String> queryKeys,
  required String context,
}) async {
  final response =
      await http.get(Uri.parse('http://$host/__admin/requests?limit=1'));
  expect(
    response.statusCode,
    200,
    reason: '$context: could not read the WireMock request journal',
  );
  final entries = (jsonDecode(response.body)
      as Map<String, Object?>)['requests'] as List<Object?>;
  expect(
    entries,
    isNotEmpty,
    reason: '$context: WireMock recorded no request at all',
  );
  final request = (entries.first! as Map<String, Object?>)['request']!
      as Map<String, Object?>;
  final url = Uri.parse(request['url']! as String);

  expect(request['method'], method, reason: '$context: wrong HTTP method');
  expect(url.path, path, reason: '$context: wrong request path');
  expect(
    url.queryParameters.keys.toSet(),
    queryKeys,
    reason: '$context: wrong query parameters',
  );
}

/// Discards the WireMock request journal so the next assertion reads only
/// requests this test made.
Future<void> resetRequestJournal(String host) async {
  final response =
      await http.delete(Uri.parse('http://$host/__admin/requests'));
  expect(
    response.statusCode,
    anyOf(200, 204),
    reason: 'could not reset the WireMock request journal',
  );
}
