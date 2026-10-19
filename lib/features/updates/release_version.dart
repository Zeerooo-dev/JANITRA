class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion._(
    this.major,
    this.minor,
    this.patch,
    this.preRelease,
    this.name,
  );

  final BigInt major;
  final BigInt minor;
  final BigInt patch;
  final List<String> preRelease;
  final String name;

  static ReleaseVersion parse(String value) {
    if (value.length > 256) throw const FormatException('Version too long');
    final match = RegExp(
      r'^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).firstMatch(value);
    if (match == null) throw const FormatException('Invalid release version');
    final pre = match[4]?.split('.') ?? <String>[];
    for (final part in pre) {
      if (RegExp(r'^0[0-9]+$').hasMatch(part)) {
        throw const FormatException('Invalid prerelease number');
      }
    }
    return ReleaseVersion._(
      BigInt.parse(match[1]!),
      BigInt.parse(match[2]!),
      BigInt.parse(match[3]!),
      pre,
      value.startsWith('v') ? value.substring(1) : value,
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      final numberA = BigInt.tryParse(a);
      final numberB = BigInt.tryParse(b);
      final result = numberA != null && numberB != null
          ? numberA.compareTo(numberB)
          : numberA != null
          ? -1
          : numberB != null
          ? 1
          : a.compareTo(b);
      if (result != 0) return result;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}
