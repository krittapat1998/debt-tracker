import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../domain/models/enums.dart';

/// The icon set the app draws with, while one is being picked:
/// `--dart-define=ICON_STYLE=phosphor` for Phosphor duotone, otherwise
/// Material rounded.
const _usePhosphor = String.fromEnvironment('ICON_STYLE') == 'phosphor';

/// An icon by what it stands for, so every screen shows the same thing
/// the same way.
enum Glyph {
  totalDebt(Icons.account_balance_wallet_rounded, PhosphorIconsDuotone.wallet),
  dueThisMonth(Icons.event_available_rounded, PhosphorIconsDuotone.calendarCheck),
  paid(Icons.check_circle_rounded, PhosphorIconsDuotone.checkCircle),
  interest(Icons.percent_rounded, PhosphorIconsDuotone.percent),
  debtFree(Icons.flag_rounded, PhosphorIconsDuotone.flag),
  dueDate(Icons.event_rounded, PhosphorIconsDuotone.calendarBlank),
  overdue(Icons.warning_amber_rounded, PhosphorIconsDuotone.warning),
  info(Icons.info_rounded, PhosphorIconsDuotone.info),
  payFirst(Icons.trending_down_rounded, PhosphorIconsDuotone.chartLineDown),
  hottest(Icons.local_fire_department_rounded, PhosphorIconsDuotone.flame),
  creditCard(Icons.credit_card_rounded, PhosphorIconsDuotone.creditCard),
  cashCard(Icons.local_atm_rounded, PhosphorIconsDuotone.money),
  loan(Icons.account_balance_rounded, PhosphorIconsDuotone.bank),
  otherDebt(Icons.account_balance_wallet_rounded, PhosphorIconsDuotone.wallet),
  limit(Icons.speed_rounded, PhosphorIconsDuotone.gauge),
  installments(Icons.view_timeline_rounded, PhosphorIconsDuotone.calendarDots),
  sms(Icons.sms_rounded, PhosphorIconsDuotone.chatText),
  addCard(Icons.add_card_rounded, PhosphorIconsDuotone.plusCircle),
  pay(Icons.payments_rounded, PhosphorIconsDuotone.handCoins),
  spend(Icons.shopping_bag_rounded, PhosphorIconsDuotone.shoppingBag),
  withdraw(Icons.local_atm_rounded, PhosphorIconsDuotone.money),
  statement(Icons.edit_note_rounded, PhosphorIconsDuotone.notePencil),
  history(Icons.receipt_long_rounded, PhosphorIconsDuotone.receipt),
  recurring(Icons.autorenew_rounded, PhosphorIconsDuotone.arrowsClockwise),
  prepay(Icons.rocket_launch_rounded, PhosphorIconsDuotone.rocketLaunch),
  installmentPaid(Icons.event_repeat_rounded, PhosphorIconsDuotone.repeat),
  paidInFull(Icons.done_all_rounded, PhosphorIconsDuotone.checks),
  minimum(Icons.south_rounded, PhosphorIconsDuotone.arrowCircleDown),
  calculator(Icons.calculate_rounded, PhosphorIconsDuotone.calculator),
  schedule(Icons.table_rows_rounded, PhosphorIconsDuotone.listNumbers),
  edit(Icons.edit_rounded, PhosphorIconsDuotone.pencilSimple),
  add(Icons.add_rounded, PhosphorIconsDuotone.plus),
  done(Icons.check_rounded, PhosphorIconsDuotone.check),
  next(Icons.chevron_right_rounded, PhosphorIconsRegular.caretRight),
  expand(Icons.expand_more_rounded, PhosphorIconsRegular.caretDown),
  collapse(Icons.expand_less_rounded, PhosphorIconsRegular.caretUp),
  inbox(Icons.mark_email_unread_rounded, PhosphorIconsDuotone.envelopeSimple),
  notFound(Icons.search_off_rounded, PhosphorIconsDuotone.magnifyingGlass);

  const Glyph(this._material, this._phosphor);
  final IconData _material;
  final IconData _phosphor;

  /// For widgets that take [IconData]; Phosphor shows only the outline.
  IconData get data => _usePhosphor ? _phosphor : _material;

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
}

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size, this.color});
  final Glyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => _usePhosphor
      ? PhosphorIcon(glyph._phosphor, size: size, color: color, duotoneSecondaryOpacity: 0.3)
      : Icon(glyph._material, size: size, color: color);
}

/// A card's kind at a glance: a rounded square with its icon, in the card's
/// own colors when it has one.
class AccountBadge extends StatelessWidget {
  const AccountBadge(this.type, {super.key, this.size = 40});
  final AccountType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Center(
        child: GlyphIcon(Glyph.forAccount(type), size: size * 0.55, color: cs.onSecondaryContainer),
      ),
    );
  }
}
