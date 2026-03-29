import 'package:mobile/models/event_model.dart';

List<CivicEvent> sortEventsByLastActivity(Iterable<CivicEvent> events) {
  final ordered = events.toList(growable: false);
  ordered.sort((a, b) {
    final byActivity = b.lastActivityAt.compareTo(a.lastActivityAt);
    if (byActivity != 0) return byActivity;

    final byFirstSeen = b.firstSeen.compareTo(a.firstSeen);
    if (byFirstSeen != 0) return byFirstSeen;

    return a.hashtag.compareTo(b.hashtag);
  });
  return ordered;
}
