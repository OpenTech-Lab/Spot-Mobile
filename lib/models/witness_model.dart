import 'package:mobile/models/event_model.dart';

/// The nature of a witness signal.
enum WitnessType {
  /// "I was there / I saw this."
  seen,

  /// "I can confirm this is real."
  confirm,

  /// "I was there and this did NOT happen."
  deny,
}

/// A structured human signal indicating observation or judgement about an event.
///
/// Witnesses are published as Nostr kind-1 events with a [`witness`] tag.
/// They are lightweight — no media required.
class Witness {
  /// SHA-256 of the serialized Nostr event (hex).
  final String id;

  /// [CivicEvent.hashtag] this witness applies to.
  final String eventId;

  /// Author's Nostr pubkey.
  final String userId;

  /// Nature of the signal.
  final WitnessType type;

  /// Optional GPS location where the witness was when they sent this signal.
  final double? lat;
  final double? lon;

  /// When the witness signal was published.
  final DateTime timestamp;

  /// Computed influence weight 0.0–1.0 (higher = more trustworthy).
  final double weight;

  const Witness({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.type,
    this.lat,
    this.lon,
    required this.timestamp,
    required this.weight,
  });

  /// Parses a Nostr kind-1 event that contains a `witness` tag.
  ///
  /// Returns null if the event does not carry a valid witness signal.
  static Witness? fromNostrEvent(NostrEvent event, {double weight = 0.5}) {
    final witnessTag = event.getTagValue('witness');
    if (witnessTag == null) return null;

    final type = _parseType(witnessTag);
    if (type == null) return null;

    final hashtag = event.getTagValue('t');
    if (hashtag == null) return null;

    // geo tag: ["geo", "lat", "lon"]
    double? lat, lon;
    for (final tag in event.tags) {
      if (tag.isNotEmpty && tag[0] == 'geo' && tag.length >= 3) {
        lat = double.tryParse(tag[1]);
        lon = double.tryParse(tag[2]);
        break;
      }
    }

    return Witness(
      id: event.id,
      eventId: hashtag,
      userId: event.pubkey,
      type: type,
      lat: lat,
      lon: lon,
      timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      weight: weight,
    );
  }

  static WitnessType? _parseType(String value) => switch (value) {
        'seen' => WitnessType.seen,
        'confirm' => WitnessType.confirm,
        'deny' => WitnessType.deny,
        _ => null,
      };
}
