/// Centralised app configuration.
///
/// Toggle [useTestRelays] to switch between production and test relay sets.
abstract final class AppConfig {
  AppConfig._();

  /// Set to `true` to use test relays, `false` for production.
  static const useTestRelays = true;

  // ── Nostr relays ──────────────────────────────────────────────────────────

  static const productionRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
    'wss://relay.snort.social',
  ];

  static const testRelays = [
    'wss://testnet.plebnet.dev',
    'wss://relay.staging.geyser.fund',
    'wss://nostrja-world-relays-test.heguro.com',
  ];

  static List<String> get relays =>
      useTestRelays ? testRelays : productionRelays;
}
