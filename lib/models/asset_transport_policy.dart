enum AssetTransportPolicy { off, wifiOnly, always }

AssetTransportPolicy parseAssetTransportPolicy(String? value) {
  return switch (value) {
    'off' => AssetTransportPolicy.off,
    'always' => AssetTransportPolicy.always,
    _ => AssetTransportPolicy.wifiOnly,
  };
}

extension AssetTransportPolicyX on AssetTransportPolicy {
  String get storageValue => switch (this) {
    AssetTransportPolicy.off => 'off',
    AssetTransportPolicy.wifiOnly => 'wifi_only',
    AssetTransportPolicy.always => 'always',
  };

  String get label => switch (this) {
    AssetTransportPolicy.off => 'Off',
    AssetTransportPolicy.wifiOnly => 'Wi-Fi only',
    AssetTransportPolicy.always => 'Always',
  };

  String get description => switch (this) {
    AssetTransportPolicy.off =>
      'Do not share or fetch full images and videos over peer transport.',
    AssetTransportPolicy.wifiOnly =>
      'Allow peer image/video transport only while connected to Wi-Fi or Ethernet.',
    AssetTransportPolicy.always =>
      'Allow peer image/video transport on any network, including mobile data.',
  };
}
