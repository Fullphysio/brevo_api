import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'multipart.dart';
import 'request_options.dart';
import 'transport.dart';

/// A client for the Brevo API.
///
/// Wires HTTP transport — `api-key` authentication, timeouts, retries and
/// error mapping — to the typed resources reachable through its namespaces.
/// One instance should be reused for the lifetime of the process; call
/// [close] once it is no longer needed.
///
/// Unlike `@getbrevo/brevo`, nothing is read from environment variables:
/// every credential is passed explicitly, which is what makes the client
/// portable across Flutter apps, CLIs and Cloud Functions, and testable.
final class BrevoClient {
  /// Creates a client authenticated with [apiKey].
  ///
  /// [partnerKey] is sent as the `partner-key` header alongside the API key
  /// for partner accounts. [baseUrl] replaces `https://api.brevo.com/v3` —
  /// for tests, or for a mock server. [httpClient] is an injection seam for
  /// tests; when omitted, a fresh [http.Client] is created and owned by this
  /// instance, to be closed by [close]. [timeout] bounds each attempt and
  /// [maxRetries] caps how many times a failed attempt is retried.
  /// [defaultHeaders] are added to every request.
  BrevoClient({
    required String apiKey,
    String? partnerKey,
    Uri? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    Map<String, String> defaultHeaders = const {},
  }) : _transport = BrevoTransport(
          apiKey: apiKey,
          partnerKey: partnerKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
          timeout: timeout,
          maxRetries: maxRetries,
          defaultHeaders: defaultHeaders,
        );

  /// The deadline for receiving response headers on each attempt.
  final Duration timeout;

  /// How many times a failed attempt is retried on top of the first one.
  final int maxRetries;

  final BrevoTransport _transport;

  /// Sends a JSON request and returns the decoded body.
  ///
  /// This is the primitive the typed resources are built on, exposed as an
  /// escape hatch for an endpoint this package does not model yet. [path] is
  /// the already-encoded request path with its leading slash, relative to
  /// the `/v3` prefix, such as `/contacts`; [query] repeats the key for each
  /// element of a list value; [body] is JSON-encoded when given. Returns
  /// `null` for an empty response body.
  Future<Object?> requestJson({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) =>
      _transport.requestJson(
        method: method,
        path: path,
        query: query,
        body: body,
        options: options,
      );

  /// Sends a request and discards the response body.
  Future<void> requestVoid({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) =>
      _transport.requestVoid(
        method: method,
        path: path,
        query: query,
        body: body,
        options: options,
      );

  /// Sends a request whose response is binary and returns the raw bytes.
  Future<Uint8List> requestBytes({
    required String method,
    required String path,
    Map<String, Object?>? query,
    Object? body,
    BrevoRequestOptions? options,
  }) =>
      _transport.requestBytes(
        method: method,
        path: path,
        query: query,
        body: body,
        options: options,
      );

  /// Sends a `multipart/form-data` request with string [fields] and [files]
  /// and returns the decoded JSON body.
  ///
  /// A field holding a `Map` or `List` is sent JSON-encoded; a `null` field
  /// is omitted.
  Future<Object?> requestMultipart({
    String method = 'POST',
    required String path,
    Map<String, Object?>? query,
    required Map<String, Object?> fields,
    required Map<String, BrevoFile> files,
    BrevoRequestOptions? options,
  }) =>
      _transport.requestMultipart(
        method: method,
        path: path,
        query: query,
        fields: fields,
        files: files,
        options: options,
      );

  /// Closes the underlying HTTP client, if this instance created it.
  ///
  /// Does nothing when the client was constructed with a caller-supplied
  /// `httpClient`, since that client's lifetime belongs to its caller.
  void close() => _transport.close();
}
