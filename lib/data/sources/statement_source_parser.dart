/// Common contract for every source that turns bank notifications into
/// structured events: SMS today, e-mail (Gmail API etc.) later. The data
/// model and UI only see [ParsedStatementEvent], never the source.
library;

enum StatementSourceType {
  sms('SMS'),
  email('อีเมล'),
  pasted('ข้อความที่วาง');

  const StatementSourceType(this.label);
  final String label;
}

/// A message exactly as received. Never leaves the device.
class RawStatementMessage {
  const RawStatementMessage({
    required this.source,
    required this.sender,
    required this.body,
    required this.receivedAt,
    this.subject,
    this.externalId,
  });

  final StatementSourceType source;

  /// SMS sender id / e-mail From. Empty for pasted text.
  final String sender;
  final String body;
  final DateTime receivedAt;

  /// E-mail subject (unused for SMS).
  final String? subject;

  /// Platform id (SMS _id, Gmail message id) when available.
  final String? externalId;

  /// Key used to avoid importing the same message twice. It must match
  /// between the live SMS receiver and a later inbox scan (which report
  /// different platform ids), and survive app restarts, so it is built
  /// from sender, send time (to the second) and a stable body hash.
  /// Pasted text has no real send time, so only its body counts.
  String get dedupKey => source == StatementSourceType.pasted
      ? '${source.name}|${_fnv1a(body.trim())}'
      : '${source.name}|${sender.trim().toLowerCase()}|${receivedAt.millisecondsSinceEpoch ~/ 1000}|${_fnv1a(body.trim())}';
}

/// 32-bit FNV-1a; unlike String.hashCode it is stable across runs.
String _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

enum StatementEventKind {
  statement('ยอดเรียกเก็บ'),
  payment('รับชำระ'),
  spending('ใช้จ่าย');

  const StatementEventKind(this.label);
  final String label;
}

/// Structured result of parsing one message. The user always reviews it
/// before anything is written to the ledger.
class ParsedStatementEvent {
  const ParsedStatementEvent({
    required this.kind,
    required this.amount,
    required this.occurredAt,
    required this.message,
    required this.patternId,
    this.bankId,
    this.bankName,
    this.minimumDue,
    this.dueDate,
    this.cardLast4,
  });

  final StatementEventKind kind;

  /// statement: total billed; payment: amount received; spending: amount spent.
  final double amount;
  final double? minimumDue;
  final DateTime? dueDate;
  final String? cardLast4;
  final String? bankId;
  final String? bankName;
  final DateTime occurredAt;
  final RawStatementMessage message;

  /// Which config pattern produced this (useful when tuning regexes).
  final String patternId;
}

abstract interface class StatementSourceParser {
  StatementSourceType get sourceType;

  /// Cheap check whether this parser understands the message at all.
  bool canParse(RawStatementMessage message);

  /// Returns null when the message is not a recognizable bank notice.
  ParsedStatementEvent? parse(RawStatementMessage message);
}
