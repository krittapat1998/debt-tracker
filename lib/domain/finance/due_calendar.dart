import '../../core/date_utils.dart';
import 'portfolio.dart';

enum DueEventKind {
  /// The card's bill is due (ขั้นต่ำ/ยอดเรียกเก็บ).
  cardDue('ครบกำหนดจ่ายบัตร'),

  /// An installment paid on its own (not through the card).
  installment('ค่างวด'),

  /// The card's cutoff; card-billed installments go on the card that day.
  cutoff('ตัดรอบบิล'),

  /// A recurring charge (Netflix and the like) hits the card.
  recurring('หักประจำ');

  const DueEventKind(this.label);
  final String label;

  /// Money has to go out that day.
  bool get isPayment => this == cardDue || this == installment;
}

/// Something that happens to the user's debts on a day.
class DueEvent {
  const DueEvent({
    required this.date,
    required this.kind,
    required this.accountId,
    required this.title,
    this.amount,
    this.paid = false,
  });

  final DateTime date;
  final DueEventKind kind;
  final String accountId;
  final String title;

  /// Known amount; null when the bill for that month is not out yet.
  final double? amount;
  final bool paid;
}

/// Every due date, cutoff and recurring charge of the portfolio between
/// [from] and [to] (inclusive), by date.
List<DueEvent> dueEvents(PortfolioSummary s, DateTime from, DateTime to) {
  final start = dateOnly(from);
  final end = dateOnly(to);
  bool inRange(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
  final events = <DueEvent>[];

  for (final a in s.accounts) {
    final name = a.account.name;
    final owesOnCard = a.revolvingBalance > 0.005 ||
        a.account.minimumPayment > 0 ||
        a.plans.any((p) => p.plan.includedInStatement && !p.isClosed);

    // The current bill, with its amount; later months' bills by due day.
    final stmtDue = a.statementDueDate;
    if (stmtDue != null && inRange(stmtDue) && a.account.minimumPayment > 0) {
      events.add(DueEvent(
        date: stmtDue,
        kind: DueEventKind.cardDue,
        accountId: a.account.id,
        title: name,
        amount: a.isStatementPaid ? a.account.minimumPayment : a.minimumOutstanding,
        paid: a.isStatementPaid,
      ));
    }
    final dueDay = a.account.dueDay;
    if (dueDay != null && owesOnCard) {
      for (var d = nextOccurrenceOfDay(dueDay, start); !d.isAfter(end); d = nextDayAfter(dueDay, d)) {
        if (stmtDue != null && isSameMonth(d, stmtDue)) continue;
        // Months already past have no bill to remind of.
        if (d.isBefore(s.today)) continue;
        events.add(DueEvent(date: d, kind: DueEventKind.cardDue, accountId: a.account.id, title: name));
      }
    }

    final billingDay = a.account.billingDay;
    if (billingDay != null && owesOnCard) {
      for (var d = nextOccurrenceOfDay(billingDay, start); !d.isAfter(end); d = nextDayAfter(billingDay, d)) {
        events.add(DueEvent(date: d, kind: DueEventKind.cutoff, accountId: a.account.id, title: name));
      }
    }

    for (final p in a.plans) {
      final cardBilled = p.plan.includedInStatement;
      for (final r in [...p.paidRows, ...p.projection]) {
        final d = r.dueDate;
        if (d == null || !inRange(d)) continue;
        events.add(DueEvent(
          date: d,
          kind: cardBilled ? DueEventKind.cutoff : DueEventKind.installment,
          accountId: a.account.id,
          title: '${p.plan.name} งวด ${r.number}/${p.plan.termMonths}',
          amount: r.payment,
          paid: r.isPaid,
        ));
      }
    }

    for (final c in a.recurring) {
      if (!c.active) continue;
      for (var d = c.nextDate; !d.isAfter(end); d = c.following(d)) {
        if (inRange(d)) {
          events.add(DueEvent(date: d, kind: DueEventKind.recurring, accountId: a.account.id, title: c.name, amount: c.amount));
        }
      }
    }
  }
  events.sort((x, y) {
    final c = x.date.compareTo(y.date);
    return c != 0 ? c : x.kind.index.compareTo(y.kind.index);
  });
  return events;
}
