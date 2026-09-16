import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'decode_exception.dart';
import 'exceptions.dart';
import 'multipart.dart';
import 'query_encoding.dart';
import 'request_options.dart';
import 'retry_policy.dart';
import 'version.dart';

/// The origin and path prefix of the Brevo REST API.
final Uri brevoDefaultBaseUrl = Uri.parse('https://api.brevo.com/v3');

/// Waits for [delay] before the next attempt; an injection seam for tests.
typedef BrevoSleep = Future<void> Function(Duration delay);

Future<void> _realSleep(Duration delay) => Future<void>.delayed(delay);

/// Carries out HTTP requests against Brevo, applying authentication, the
/// timeout, the retry policy and error mapping.
final class BrevoTransport {
  /// Creates a transport authenticated with [apiKey].
  BrevoTransport({
    required String apiKey,
    String? partnerKey,
    Uri? baseUrl,
    http.Client? httpClient,
    required this.timeout,
    required this.maxRetries,
    Map<String, String> defaultHeaders = const {},
    Random? random,
    BrevoSleep? sleep,
    DateTime Function()? clock,
  })  : _apiKey = apiKey,
        _partnerKey = partnerKey,
        _origin = _originOf(baseUrl ?? brevoDefaultBaseUrl),
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _defaultHeaders = Map.unmodifiable(defaultHeaders),
        _random = random,
        _sleep = sleep ?? _realSleep,
        _clock = clock ?? DateTime.now;

  /// The deadline for receiving response headers on each attempt.
  final Duration timeout;

  /// How many times a failed attempt is retried on top of the first one.
  final int maxRetries;

  final String _apiKey;
  final String? _partnerKey;
  final String _origin;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Map<String, String> _defaultHeaders;
  final Random? _random;
  final BrevoSleep _sleep;
  final DateTime Function() _clock;

  /// Sends a JSON request and returns the decoded body, or `null` for an
  /// empty body.
  Future<Object?> requestJson({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) async {
    final response = await send(
      method: method,
      path: path,
      query: query,
      body: body,
      options: options,
    );
    return _decodeJson(method, path, response);
  }

  /// Sends a request whose response body, if any, is discarded.
  Future<void> requestVoid({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) async {
    await send(
      method: method,
      path: path,
      query: query,
      body: body,
      options: options,
    );
  }

  /// Sends a request whose response is binary, such as an exported file, and
  /// returns the raw body.
  Future<Uint8List> requestBytes({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) async {
    final response = await send(
      method: method,
      path: path,
      query: query,
      body: body,
      options: options,
    );
    return response.bodyBytes;
  }

  /// Sends a `multipart/form-data` request carrying string [fields] and
  /// [files], and returns the decoded JSON body, or `null` for an empty body.
  ///
  /// A field whose value is a `Map` or `List` is sent JSON-encoded, the way
  /// `@getbrevo/brevo` serialises the `mapping` of an import; scalars are
  /// stringified. A `null` field is omitted.
  Future<Object?> requestMultipart({
    String method = 'POST',
    required String path,
    Map<String, Object?>? query,
    required Map<String, Object?> fields,
    required Map<String, BrevoFile> files,
    BrevoRequestOptions? options,
  }) async {
    final uri = _buildUri(path, query);
    final response = await _sendWithRetries(
      method: method,
      path: path,
      options: options,
      buildRequest: () {
        final request = http.MultipartRequest(method, uri);
        for (final entry in fields.entries) {
          final value = entry.value;
          if (value == null) {
            continue;
          }
          request.fields[entry.key] =
              value is Map || value is List ? jsonEncode(value) : '$value';
        }
        for (final entry in files.entries) {
          final file = entry.value;
          request.files.add(
            http.MultipartFile.fromBytes(
              entry.key,
              file.bytes,
              filename: file.filename,
              contentType: file.contentType == null
                  ? null
                  : MediaType.parse(file.contentType!),
            ),
          );
        }
        return request;
      },
    );
    return _decodeJson(method, path, response);
  }

  /// Sends one request with retries and returns the successful response.
  ///
  /// [path] is the already-encoded request path with its leading slash,
  /// relative to the `/v3` prefix; [query] is serialised by
  /// [brevoQueryEncode]; [body], when given, is JSON encoded and sent with
  /// `Content-Type: application/json`. Throws the [BrevoApiException]
  /// subtype for a non-2xx response once retries are exhausted or the status
  /// is not retryable, a [BrevoTimeoutException] when the attempt exceeded
  /// the timeout, or a [BrevoConnectionException] when it produced no
  /// response.
  Future<http.Response> send({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) {
    final uri = _buildUri(path, query);
    final bodyBytes = body == null ? null : utf8.encode(jsonEncode(body));
    return _sendWithRetries(
      method: method,
      path: path,
      options: options,
      buildRequest: () {
        final request = http.Request(method, uri);
        if (bodyBytes != null) {
          request
            ..bodyBytes = bodyBytes
            ..headers['Content-Type'] = 'application/json';
        }
        return request;
      },
    );
  }

  /// Closes the underlying HTTP client, if this transport created it.
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<http.Response> _sendWithRetries({
    required String method,
    required String path,
    required BrevoRequestOptions? options,
    required http.BaseRequest Function() buildRequest,
  }) async {
    final attemptTimeout = options?.timeout ?? timeout;
    final retries = options?.maxRetries ?? maxRetries;
    var attempt = 0;
    while (true) {
      final http.Response response;
      try {
        response = await _attempt(buildRequest(), options, attemptTimeout);
      } on TimeoutException {
        throw BrevoTimeoutException(method: method, path: path);
      } on Exception catch (error) {
        throw BrevoConnectionException(message: '$error', cause: error);
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      if (!brevoShouldRetry(
        attempt: attempt,
        maxRetries: retries,
        response: response,
      )) {
        throw brevoApiExceptionFromResponse(
          statusCode: response.statusCode,
          headers: response.headers,
          body: utf8.decode(response.bodyBytes, allowMalformed: true),
        );
      }
      await _sleep(
        brevoRetryDelay(
          attempt: attempt,
          headers: response.headers,
          random: _random,
          now: _clock(),
        ),
      );
      attempt++;
    }
  }

  Future<http.Response> _attempt(
    http.BaseRequest request,
    BrevoRequestOptions? options,
    Duration attemptTimeout,
  ) async {
    final headers = request.headers;
    headers['Accept'] = '*/*';
    headers['User-Agent'] = 'brevo_api/$brevoApiVersion (Dart)';
    headers['api-key'] = _apiKey;
    final partnerKey = _partnerKey;
    if (partnerKey != null) {
      headers['partner-key'] = partnerKey;
    }
    headers.addAll(_defaultHeaders);
    if (options != null) {
      headers.addAll(options.headers);
    }
    final pending = _httpClient.send(request);
    final http.StreamedResponse streamed;
    try {
      streamed = await pending.timeout(attemptTimeout);
    } on TimeoutException {
      _drainLate(pending);
      rethrow;
    }
    return http.Response.fromStream(streamed);
  }

  /// `Future.timeout` abandons the request but cannot cancel it; when the
  /// response does arrive, its body is read to completion so the pooled
  /// connection is released instead of staying pinned by an unread stream.
  void _drainLate(Future<http.StreamedResponse> pending) {
    unawaited(
      pending
          .then((late) => late.stream.drain<void>())
          .catchError((Object _) {}),
    );
  }

  Object? _decodeJson(String method, String path, http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    final text = utf8.decode(response.bodyBytes);
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw BrevoDecodeException(
        '$method $path: response body is not JSON (${error.message})',
      );
    }
  }

  Uri _buildUri(String path, Map<String, Object?>? query) {
    final encodedQuery = query == null ? '' : brevoQueryEncode(query);
    return Uri.parse(
      '$_origin$path${encodedQuery.isEmpty ? '' : '?$encodedQuery'}',
    );
  }

  static String _originOf(Uri baseUrl) =>
      baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
}
