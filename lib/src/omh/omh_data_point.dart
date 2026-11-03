import 'package:flutter/foundation.dart';

/// An OMH / IEEE 1752.1 schema identifier (`namespace:name:version`).
@immutable
class SchemaId {
  /// Creates a schema identifier.
  const new({
    required this.namespace,
    required this.name,
    required this.version,
  });

  /// Schema namespace, e.g. `omh` or `cairn` (DESIGN.md §5.2).
  final String namespace;

  /// Schema name, e.g. `heart-rate`.
  final String name;

  /// Schema version string, e.g. `1.0`.
  final String version;

  /// Serialises to the OMH `schema_id` object.
  Map<String, Object?> toJson() => {
    'namespace': namespace,
    'name': name,
    'version': version,
  };
}

/// The OMH `acquisition_provenance` block: where a datapoint came from
/// (DESIGN.md §4.3, §5.2).
@immutable
class AcquisitionProvenance {
  /// Creates an acquisition-provenance block.
  const new({
    required this.sourceName,
    required this.modality,
    this.sourceCreationDateTime,
  });

  /// Human-readable source/app name (e.g. `Samsung Health`).
  final String sourceName;

  /// How the data was acquired: `sensed` or `self-reported`.
  final String modality;

  /// Optional source-side creation timestamp (ISO-8601 with local offset).
  final String? sourceCreationDateTime;

  /// Serialises to the OMH `acquisition_provenance` object.
  Map<String, Object?> toJson() => {
    'source_name': sourceName,
    'modality': modality,
    'source_creation_date_time': ?sourceCreationDateTime,
  };
}

/// The header of an OMH datapoint.
@immutable
class OmhHeader {
  /// Creates an OMH datapoint header.
  const new({
    required this.id,
    required this.creationDateTime,
    required this.schemaId,
    this.provenance,
  });

  /// Globally-unique datapoint id (UUID v4).
  final String id;

  /// Header creation timestamp (ISO-8601 with local offset).
  final String creationDateTime;

  /// Identifier of the schema the body conforms to.
  final SchemaId schemaId;

  /// Optional provenance of the reading.
  final AcquisitionProvenance? provenance;

  /// Serialises to the OMH `header` object.
  Map<String, Object?> toJson() => {
    'id': id,
    'creation_date_time': creationDateTime,
    'schema_id': schemaId.toJson(),
    'acquisition_provenance': ?provenance?.toJson(),
  };
}

/// A complete OMH datapoint: a [header] plus a measure-specific [body].
@immutable
class OmhDataPoint {
  /// Creates an OMH datapoint.
  const new({required this.header, required this.body});

  /// The datapoint header (id, schema id, provenance).
  final OmhHeader header;

  /// The measure body, validated against the schema named in [header].
  final Map<String, Object?> body;

  /// Serialises to the full `{header, body}` OMH datapoint object.
  Map<String, Object?> toJson() => {'header': header.toJson(), 'body': body};
}
