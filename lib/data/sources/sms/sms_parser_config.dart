import 'dart:convert';

import '../statement_source_parser.dart';

/// Placeholders usable inside pattern strings, so each bank entry stays
/// readable instead of repeating long number/date regexes.
const smsMacros = <String, String>{
  '{AMOUNT}': r'([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
  // Requires thousands separators or satang, so a card's last 4 digits
  // next to a keyword are never mistaken for an amount.
  '{MONEY}': r'([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?|[0-9]+\.[0-9]{2})',
  '{DATE}':
      r'(\d{1,2}\s*[/\-.]\s*\d{1,2}(?:\s*[/\-.]\s*\d{2,4})?|\d{1,2}\s*(?:[ก-๙][ก-๙.]{1,11}|[A-Za-z]{3,9}\.?)(?:\s*\d{2,4})?)',
  '{CARD}': r'(\d{4})',
};

String expandMacros(String pattern) {
  var out = pattern;
  smsMacros.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

RegExp _re(String s) => RegExp(expandMacros(s), caseSensitive: false, unicode: true);

List<RegExp> _reList(Object? v) {
  if (v == null) return const [];
  if (v is String) return [_re(v)];
  return [for (final s in v as List) _re(s as String)];
}

List<String> _strList(Object? v) =>
    v == null ? const [] : [for (final s in v as List) s as String];

class BankProfile {
  const BankProfile({
    required this.id,
    required this.name,
    this.senderIds = const [],
    this.keywords = const [],
  });

  final String id;
  final String name;

  /// SMS sender names (matched case-insensitively, exact or prefix).
  final List<String> senderIds;

  /// Words in the body that identify the bank for pasted text.
  final List<String> keywords;

  factory BankProfile.fromJson(Map<String, Object?> j) => BankProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        senderIds: _strList(j['senderIds']),
        keywords: _strList(j['keywords']),
      );

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'senderIds': senderIds, 'keywords': keywords};

  bool matchesSender(String sender) {
    final s = sender.trim().toLowerCase();
    if (s.isEmpty) return false;
    return senderIds.any((id) {
      final i = id.toLowerCase();
      return s == i || s.startsWith(i);
    });
  }

  bool matchesBody(String body) {
    final b = body.toLowerCase();
    return keywords.any((k) => b.contains(k.toLowerCase()));
  }
}

/// One way a bank phrases a notice. Every field is a list of regexes tried
/// in order; the first capture group of the first match wins.
class SmsPattern {
  SmsPattern({
    required this.id,
    required this.bankId,
    required this.kind,
    required this.trigger,
    required this.amount,
    this.minimum = const [],
    this.dueDate = const [],
    this.card = const [],
    this.date = const [],
    this.priority = 100,
    this.source,
  });

  final String id;

  /// Bank id, or "*" for a pattern that applies to any bank.
  final String bankId;
  final StatementEventKind kind;
  final RegExp trigger;
  final List<RegExp> amount;
  final List<RegExp> minimum;
  final List<RegExp> dueDate;
  final List<RegExp> card;

  /// Transaction date inside the text (falls back to the receive time).
  final List<RegExp> date;
  final int priority;

  /// Original JSON, kept so custom patterns can be edited and re-saved.
  final Map<String, Object?>? source;

  bool get isGeneric => bankId == '*';

  factory SmsPattern.fromJson(Map<String, Object?> j) => SmsPattern(
        id: j['id'] as String,
        bankId: (j['bankId'] as String?) ?? '*',
        kind: StatementEventKind.values.byName(j['kind'] as String),
        trigger: _re(j['trigger'] as String),
        amount: _reList(j['amount']),
        minimum: _reList(j['minimum']),
        dueDate: _reList(j['dueDate']),
        card: _reList(j['card']),
        date: _reList(j['date']),
        priority: (j['priority'] as num?)?.toInt() ?? 100,
        source: j,
      );
}

/// Banks + patterns + global exclusions (e.g. OTP messages).
class SmsParserConfig {
  SmsParserConfig({
    required this.banks,
    required this.patterns,
    this.exclude = const [],
  });

  factory SmsParserConfig.fromJson(Map<String, Object?> j) => SmsParserConfig(
        banks: [
          for (final b in (j['banks'] as List? ?? const []))
            BankProfile.fromJson((b as Map).cast<String, Object?>()),
        ],
        patterns: [
          for (final p in (j['patterns'] as List? ?? const []))
            SmsPattern.fromJson((p as Map).cast<String, Object?>()),
        ],
        exclude: _reList(j['exclude']),
      );

  factory SmsParserConfig.fromJsonString(String s) =>
      SmsParserConfig.fromJson((jsonDecode(s) as Map).cast<String, Object?>());

  final List<BankProfile> banks;
  final List<SmsPattern> patterns;
  final List<RegExp> exclude;

  /// User patterns are layered on top of the bundled ones; a custom bank or
  /// pattern with an existing id replaces the bundled entry.
  SmsParserConfig merge(SmsParserConfig other) {
    final banksById = {for (final b in banks) b.id: b, for (final b in other.banks) b.id: b};
    final patternsById = {for (final p in patterns) p.id: p, for (final p in other.patterns) p.id: p};
    return SmsParserConfig(
      banks: banksById.values.toList(),
      patterns: patternsById.values.toList(),
      exclude: [...exclude, ...other.exclude],
    );
  }

  BankProfile? bankById(String? id) {
    for (final b in banks) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Every known sender id, used by the Android receiver as a whitelist so
  /// unrelated SMS (OTP, chats) are never even stored.
  List<String> get allSenderIds => {for (final b in banks) ...b.senderIds}.toList();
}
