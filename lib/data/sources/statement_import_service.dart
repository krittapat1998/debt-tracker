import '../../domain/finance/portfolio.dart';
import '../../domain/models/account.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/spending.dart';
import '../services/ledger_service.dart';
import 'statement_source_parser.dart';

/// What the user confirmed (possibly after editing) for one parsed event.
class ImportDecision {
  const ImportDecision({
    required this.event,
    required this.kind,
    required this.accountId,
    required this.amount,
    required this.date,
    this.minimumDue,
    this.dueDate,
    this.creditLineId,
    this.planId,
    this.paymentType = PaymentType.other,
    this.note,
  });

  final ParsedStatementEvent event;
  final StatementEventKind kind;
  final String accountId;
  final double amount;
  final DateTime date;
  final double? minimumDue;
  final DateTime? dueDate;
  final String? creditLineId;
  final String? planId;
  final PaymentType paymentType;
  final String? note;
}

/// Source-independent import pipeline: parse with whichever parser
/// understands the message, suggest the matching account, then write the
/// user-confirmed result through [LedgerService].
class StatementImportService {
  StatementImportService(this.parsers);

  final List<StatementSourceParser> parsers;

  ParsedStatementEvent? parse(RawStatementMessage message) {
    for (final p in parsers) {
      if (!p.canParse(message)) continue;
      final e = p.parse(message);
      if (e != null) return e;
    }
    return null;
  }

  List<ParsedStatementEvent> parseAll(Iterable<RawStatementMessage> messages) =>
      [for (final m in messages) ?parse(m)];

  /// Same card digits wins; otherwise the only account of that bank.
  String? suggestAccount(ParsedStatementEvent e, List<Account> accounts) {
    if (e.cardLast4 != null) {
      for (final a in accounts) {
        if (a.cardLast4 != null && a.cardLast4 == e.cardLast4) return a.id;
      }
    }
    if (e.bankId != null) {
      final sameBank = accounts.where((a) => a.issuer == e.bankId).toList();
      if (sameBank.length == 1) return sameBank.first.id;
    }
    return accounts.length == 1 ? accounts.first.id : null;
  }

  /// Guess the payment type from the amount and the current statement.
  PaymentType suggestPaymentType(double amount, AccountSummary? s) {
    if (s == null) return PaymentType.other;
    final a = s.account;
    if (a.statementBalance > 0 && amount >= s.statementOutstanding - 0.01) return PaymentType.full;
    if (a.minimumPayment > 0 && amount >= s.minimumOutstanding - 0.01) {
      return amount > a.minimumPayment + 0.01 ? PaymentType.extra : PaymentType.minimum;
    }
    return PaymentType.other;
  }

  Future<void> commit(ImportDecision d, LedgerService ledger) async {
    switch (d.kind) {
      case StatementEventKind.statement:
        await ledger.applyStatement(
          accountId: d.accountId,
          statementBalance: d.amount,
          minimumPayment: d.minimumDue ?? 0,
          statementDate: d.date,
          dueDate: d.dueDate,
        );
      case StatementEventKind.payment:
        await ledger.recordPayment(Payment(
          id: newId(),
          accountId: d.accountId,
          creditLineId: d.planId == null ? d.creditLineId : null,
          planId: d.planId,
          date: d.date,
          amount: d.amount,
          type: d.paymentType,
          prepaymentMode: d.paymentType == PaymentType.extra && d.planId != null
              ? PrepaymentMode.reduceTerm
              : null,
          note: d.note,
          source: d.event.message.source == StatementSourceType.email
              ? PaymentSource.email
              : PaymentSource.sms,
          createdAt: DateTime.now(),
        ));
      case StatementEventKind.spending:
        // A recurring charge (e.g. Netflix) may have recorded it already.
        if (d.creditLineId != null && !await ledger.coveredByRecurring(d.accountId, d.amount, d.date)) {
          await ledger.recordSpending(Spending(
            id: newId(),
            accountId: d.accountId,
            creditLineId: d.creditLineId,
            date: d.date,
            amount: d.amount,
            source: d.event.message.source == StatementSourceType.email
                ? PaymentSource.email
                : PaymentSource.sms,
            createdAt: DateTime.now(),
          ));
        }
    }
  }
}
