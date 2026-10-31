import '../date_text_parser.dart';
import '../statement_source_parser.dart';
import 'sms_parser_config.dart';

/// Parses bank SMS (or SMS text pasted by the user on iOS) entirely on the
/// device using the regex config in `assets/sms_patterns.json` plus any
/// user-defined patterns.
class SmsParserService implements StatementSourceParser {
  SmsParserService(this.config);

  final SmsParserConfig config;

  @override
  StatementSourceType get sourceType => StatementSourceType.sms;

  @override
  bool canParse(RawStatementMessage message) =>
      (message.source == StatementSourceType.sms || message.source == StatementSourceType.pasted) &&
      message.body.trim().isNotEmpty;

  BankProfile? identifyBank(RawStatementMessage m) {
    for (final b in config.banks) {
      if (b.matchesSender(m.sender)) return b;
    }
    for (final b in config.banks) {
      if (b.matchesBody(m.body)) return b;
    }
    return null;
  }

  /// True when the sender is a known bank (used to filter the inbox).
  bool isBankSender(String sender) => config.banks.any((b) => b.matchesSender(sender));

  @override
  ParsedStatementEvent? parse(RawStatementMessage message) {
    if (!canParse(message)) return null;
    final body = normalizeDigits(message.body).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (config.exclude.any((r) => r.hasMatch(body))) return null;

    final bank = identifyBank(message);
    final candidates = config.patterns
        .where((p) => p.isGeneric || p.bankId == bank?.id)
        .toList()
      ..sort((a, b) {
        // Bank-specific patterns first, then by priority.
        if (a.isGeneric != b.isGeneric) return a.isGeneric ? 1 : -1;
        return a.priority.compareTo(b.priority);
      });

    for (final p in candidates) {
      if (!p.trigger.hasMatch(body)) continue;
      final amountText = _first(p.amount, body);
      final amount = amountText == null ? null : parseAmountText(amountText);
      if (amount == null || amount <= 0) continue;

      final minText = _first(p.minimum, body);
      final dueText = _first(p.dueDate, body);
      final dateText = _first(p.date, body);
      final occurred = (dateText == null
              ? null
              : parseDateText(dateText, reference: message.receivedAt)) ??
          message.receivedAt;

      return ParsedStatementEvent(
        kind: p.kind,
        amount: amount,
        minimumDue: minText == null ? null : parseAmountText(minText),
        dueDate: dueText == null ? null : parseDateText(dueText, reference: message.receivedAt),
        cardLast4: _first(p.card, body),
        bankId: bank?.id,
        bankName: bank?.name,
        occurredAt: occurred,
        message: message,
        patternId: p.id,
      );
    }
    return null;
  }

  static String? _first(List<RegExp> regexes, String body) {
    for (final r in regexes) {
      final m = r.firstMatch(body);
      if (m != null && m.groupCount >= 1 && m.group(1) != null) return m.group(1)!.trim();
    }
    return null;
  }
}
