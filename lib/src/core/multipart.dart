import 'dart:typed_data';

import 'package:meta/meta.dart';

/// A file to upload as one part of a `multipart/form-data` request — the
/// CSV of a companies or deals import, or an attachment for a CRM record.
@immutable
final class BrevoFile {
  /// Creates a file part from raw [bytes].
  ///
  /// [filename] is sent in the part's `Content-Disposition`; [contentType]
  /// in its `Content-Type`, defaulting to `application/octet-stream` when
  /// omitted.
  const BrevoFile({
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  /// The file contents.
  final Uint8List bytes;

  /// The file name Brevo sees, such as `contacts.csv`.
  final String filename;

  /// The MIME type of [bytes], such as `text/csv`, or `null` for
  /// `application/octet-stream`.
  final String? contentType;
}
