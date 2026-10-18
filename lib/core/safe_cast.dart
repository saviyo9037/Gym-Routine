/// Tolerant readers for values coming out of SQLite / JSON.
///
/// A database written by an older build, an imported backup or a manual edit
/// can hold a number where text is expected (or the reverse). `as int?` would
/// throw and take the whole screen down; these helpers convert or return null
/// so the models can fall back to their defaults.
int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.toInt() : null;
  if (v is String) {
    return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.toInt();
  }
  if (v is bool) return v ? 1 : 0;
  return null;
}

double? asDouble(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  if (v is bool) return v ? 1.0 : 0.0;
  return null;
}

String? asStr(Object? v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}
