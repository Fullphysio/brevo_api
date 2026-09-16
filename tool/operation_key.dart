/// The operation-key space every tool in this directory shares.
///
/// The generator, the upstream extractor and the WireMock vendorer each line
/// operations up by verb and path template — against the specification,
/// against `@getbrevo/brevo` and against Brevo's mappings respectively — and
/// all three have to agree on what that key looks like, or they stop
/// matching each other without saying so. The rules therefore live here, not
/// once per tool.
library;

/// The HTTP methods a path item can declare that this package maps.
const Set<String> httpMethods = {'get', 'post', 'put', 'patch', 'delete'};

/// Reduces a path template to the form used for comparison, so that the same
/// endpoint named `/contacts/{identifier}` in one source and `/contacts/{id}`
/// in another both become `/contacts/{}`. A path is always rooted.
String normalisePathTemplate(String path) {
  final normalised = path.replaceAll(RegExp(r'\{[^}]*\}'), '{}');
  return normalised.startsWith('/') ? normalised : '/$normalised';
}

/// The comparable key for one operation, such as `GET /contacts/{}`.
String normalisedOperationKey(String method, String path) =>
    '${method.toUpperCase()} ${normalisePathTemplate(path)}';
