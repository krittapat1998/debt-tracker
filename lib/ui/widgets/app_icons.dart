import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/finance/due_calendar.dart';
import '../../domain/models/enums.dart';

/// An icon by what it stands for, so every screen shows the same thing the
/// same way. Phosphor duotone throughout; arrows and small marks use the
/// regular weight, where a tinted fill would read as a solid shape.
enum Glyph {
  // Money and debts.
  totalDebt(PhosphorIconsDuotone.wallet),
  dueThisMonth(PhosphorIconsDuotone.calendarCheck),
  paid(PhosphorIconsDuotone.checkCircle),
  interest(PhosphorIconsDuotone.percent),
  debtFree(PhosphorIconsDuotone.flag),
  payFirst(PhosphorIconsDuotone.chartLineDown),
  hottest(PhosphorIconsDuotone.flame),
  best(PhosphorIconsDuotone.star),
  celebrate(PhosphorIconsDuotone.confetti),
  limit(PhosphorIconsDuotone.gauge),
  installments(PhosphorIconsDuotone.calendarDots),
  earlyClosure(PhosphorIconsDuotone.lockSimple),

  // Kinds of account.
  creditCard(PhosphorIconsDuotone.creditCard),
  cashCard(PhosphorIconsDuotone.money),
  loan(PhosphorIconsDuotone.bank),
  otherDebt(PhosphorIconsDuotone.wallet),
  noCards(PhosphorIconsDuotone.prohibit),

  // Dates.
  dueDate(PhosphorIconsDuotone.calendarBlank),
  overdue(PhosphorIconsDuotone.warning),
  cutoff(PhosphorIconsDuotone.scissors),
  clock(PhosphorIconsDuotone.clock),
  hourglass(PhosphorIconsDuotone.hourglass),

  // What gets recorded.
  pay(PhosphorIconsDuotone.handCoins),
  spend(PhosphorIconsDuotone.shoppingBag),
  withdraw(PhosphorIconsDuotone.money),
  statement(PhosphorIconsDuotone.notePencil),
  history(PhosphorIconsDuotone.receipt),
  recurring(PhosphorIconsDuotone.arrowsClockwise),
  prepay(PhosphorIconsDuotone.rocketLaunch),
  installmentPaid(PhosphorIconsDuotone.repeat),
  paidInFull(PhosphorIconsDuotone.checks),
  minimum(PhosphorIconsDuotone.arrowCircleDown),
  schedule(PhosphorIconsDuotone.listNumbers),
  calculator(PhosphorIconsDuotone.calculator),
  chart(PhosphorIconsDuotone.chartLineDown),

  // SMS and settings.
  sms(PhosphorIconsDuotone.chatText),
  smsRules(PhosphorIconsDuotone.listChecks),
  inbox(PhosphorIconsDuotone.envelopeSimple),
  paste(PhosphorIconsDuotone.clipboardText),
  scan(PhosphorIconsDuotone.magnifyingGlass),
  bank(PhosphorIconsDuotone.bank),
  theme(PhosphorIconsDuotone.palette),
  autoTheme(PhosphorIconsDuotone.circleHalf),
  notifications(PhosphorIconsDuotone.bell),
  testNotification(PhosphorIconsDuotone.bellRinging),
  backup(PhosphorIconsDuotone.floppyDisk),
  lockedBackup(PhosphorIconsDuotone.lockKey),
  spreadsheet(PhosphorIconsDuotone.table),
  restore(PhosphorIconsDuotone.clockCounterClockwise),
  privacy(PhosphorIconsDuotone.shieldCheck),
  appLock(PhosphorIconsDuotone.fingerprint),
  unlock(PhosphorIconsDuotone.lockOpen),
  about(PhosphorIconsDuotone.info),
  developer(PhosphorIconsDuotone.code),
  noColor(PhosphorIconsDuotone.prohibit),

  // Navigation (filled when selected).
  home(PhosphorIconsDuotone.squaresFour, PhosphorIconsFill.squaresFour),
  calendar(PhosphorIconsDuotone.calendar, PhosphorIconsFill.calendar),
  historyTab(PhosphorIconsDuotone.receipt, PhosphorIconsFill.receipt),
  calculatorTab(PhosphorIconsDuotone.calculator, PhosphorIconsFill.calculator),
  settings(PhosphorIconsDuotone.gear, PhosphorIconsFill.gear),

  // Actions and small marks.
  addCard(PhosphorIconsDuotone.plusCircle),
  add(PhosphorIconsRegular.plus),
  remove(PhosphorIconsDuotone.minusCircle),
  delete(PhosphorIconsDuotone.trash),
  edit(PhosphorIconsDuotone.pencilSimple),
  done(PhosphorIconsRegular.check),
  clear(PhosphorIconsRegular.x),
  info(PhosphorIconsDuotone.info),
  notFound(PhosphorIconsDuotone.magnifyingGlass),
  next(PhosphorIconsRegular.caretRight),
  previous(PhosphorIconsRegular.caretLeft),
  expand(PhosphorIconsRegular.caretDown),
  collapse(PhosphorIconsRegular.caretUp);

  const Glyph(this.icon, [this.filled]);
  final IconData icon;

  /// Solid version, for a selected tab.
  final IconData? filled;

  static Glyph forAccount(AccountType t) => switch (t) {
        AccountType.creditCard => Glyph.creditCard,
        AccountType.cashCard => Glyph.cashCard,
        AccountType.personalLoan => Glyph.loan,
        AccountType.other => Glyph.otherDebt,
      };

  static Glyph forPayment(PaymentType t) => switch (t) {
        PaymentType.extra => Glyph.prepay,
        PaymentType.installment => Glyph.installmentPaid,
        PaymentType.full => Glyph.paidInFull,
        PaymentType.minimum => Glyph.minimum,
        PaymentType.other => Glyph.pay,
      };

  static Glyph forDueEvent(DueEventKind k) => switch (k) {
        DueEventKind.cardDue => Glyph.creditCard,
        DueEventKind.installment => Glyph.installmentPaid,
        DueEventKind.cutoff => Glyph.cutoff,
        DueEventKind.recurring => Glyph.recurring,
      };
}

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size, this.color, this.filled = false});
  final Glyph glyph;
  final double? size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) => PhosphorIcon(
        filled ? glyph.filled ?? glyph.icon : glyph.icon,
        size: size,
        color: color,
        duotoneSecondaryOpacity: 0.3,
      );
}

/// A card's kind at a glance: a rounded square with its icon, in the card's
/// own colors when it has one.
class AccountBadge extends StatelessWidget {
  const AccountBadge(this.type, {super.key, this.size = 36});
  final AccountType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Center(child: GlyphIcon(Glyph.forAccount(type), size: size * 0.58, color: cs.onSecondaryContainer)),
    );
  }
}
