/// Why the phone has no home-network address to scan from (2.9.4), so the
/// setup screen can say what to do instead of "No local network". Three
/// users in a day tapped Scan again and again on that message (2026-10-18).
enum NoNetwork {
  /// Only mobile data is up: Wi-Fi is off or not joined.
  mobileData,

  /// No network at all.
  offline,

  /// Something else (Wi-Fi without an IPv4 address, an unknown interface),
  /// or the interfaces could not be read. Never claims mobile data.
  unknown,
}

/// Classifies the phone's interfaces, every address family, when no home
/// address was found. Link-local addresses (fe80::, 169.254.) don't count:
/// Wi-Fi that is on but not joined has only those.
NoNetwork whyNoNetwork(List<({String name, String ip})> addresses) {
  final real = [
    for (final a in addresses)
      if (!_isLinkLocal(a.ip)) a,
  ];
  if (real.isEmpty) return NoNetwork.offline;
  // Wi-Fi or Ethernet with an address the scan can't use (IPv6 only).
  if (real.any((a) => _isHome(a.name))) return NoNetwork.unknown;
  if (real.any((a) => _isMobile(a.name))) return NoNetwork.mobileData;
  return NoNetwork.unknown;
}

bool _isLinkLocal(String ip) {
  final lower = ip.toLowerCase();
  return lower.startsWith('fe80') || ip.startsWith('169.254.');
}

bool _isHome(String name) =>
    name.startsWith('wlan') || name.startsWith('eth') || name.startsWith('en');

bool _isMobile(String name) =>
    name.startsWith('rmnet') ||
    name.startsWith('v4-rmnet') ||
    name.startsWith('ccmni') ||
    name.startsWith('pdp') ||
    name.startsWith('seth') ||
    name.startsWith('clat');
