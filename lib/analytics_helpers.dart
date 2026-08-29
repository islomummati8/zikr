import 'dart:convert';

// Small helper file might be unused — kept for future extraction of analytics logic.
// The main implementation is embedded into main.dart for simplicity in this change.

String encodePrayerRecords(Map<String, Map<String, Map<String, dynamic>>> m) => jsonEncode(m);

Map<String, Map<String, Map<String, dynamic>>> decodePrayerRecords(String s) {
  final Map raw = jsonDecode(s);
  final out = <String, Map<String, Map<String, dynamic>>>{};
  raw.forEach((date, val) {
    final Map day = val as Map;
    final dayMap = <String, Map<String, dynamic>>{};
    day.forEach((k, v) => dayMap[k.toString()] = Map<String, dynamic>.from(v as Map));
    out[date.toString()] = dayMap;
  });
  return out;
}
