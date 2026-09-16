/// A pure Dart client for the Brevo API.
///
/// Typed resources for transactional email and SMS, contacts, campaigns,
/// CRM and every other Brevo v3 endpoint, from Dart servers, CLIs and
/// Flutter apps alike. No Flutter dependency.
///
/// The runtime behaviour is a deliberate port of the official Node.js
/// client, `@getbrevo/brevo` 6.0.3 — retry policy, backoff, error mapping,
/// query and path encoding and body serialisation all follow that
/// implementation. Typed models and resource methods are generated from
/// Brevo's OpenAPI specification.
library;

export 'src/core/client.dart' show BrevoClient;
export 'src/core/decode_exception.dart' show BrevoDecodeException;
export 'src/core/exceptions.dart'
    show
        BrevoApiException,
        BrevoBadRequestException,
        BrevoConflictException,
        BrevoConnectionException,
        BrevoException,
        BrevoExpectationFailedException,
        BrevoFailedDependencyException,
        BrevoForbiddenException,
        BrevoInternalServerException,
        BrevoMethodNotAllowedException,
        BrevoNotFoundException,
        BrevoPaymentRequiredException,
        BrevoPreconditionFailedException,
        BrevoTimeoutException,
        BrevoTooEarlyException,
        BrevoTooManyRequestsException,
        BrevoUnauthorizedException,
        BrevoUnexpectedStatusException,
        BrevoUnprocessableEntityException,
        BrevoUnsupportedMediaTypeException;
export 'src/core/json_reading.dart' show BrevoJsonReading;
export 'src/core/multipart.dart' show BrevoFile;
export 'src/core/offset_page.dart' show BrevoOffsetPage, BrevoOffsetPageFetcher;
export 'src/core/open_enum.dart' show BrevoOpenEnum;
export 'src/core/request_options.dart' show BrevoRequestOptions;
export 'src/core/transport.dart' show brevoDefaultBaseUrl;
export 'src/core/version.dart' show brevoApiVersion;
