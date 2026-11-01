enum AccountType {
  creditCard('บัตรเครดิต', 'ยอดรูดบัตร', 'ใช้จ่าย'),
  cashCard('บัตรกดเงินสด', 'ยอดกดเงินสด', 'กดเงินสด'),
  personalLoan('สินเชื่อส่วนบุคคล', 'ยอดเบิกใช้', 'ใช้จ่าย'),
  other('อื่นๆ', 'ยอดใช้วงเงิน', 'ใช้จ่าย');

  const AccountType(this.label, this.revolvingLabel, this.spendingWord);
  final String label;

  /// Plain name for a sub-limit's balance outside installment plans.
  final String revolvingLabel;

  /// What one new use of a sub-limit is called, as in "เพิ่มยอด…":
  /// a purchase on a credit card, a withdrawal on a cash card.
  final String spendingWord;

  static AccountType fromName(String? name) =>
      AccountType.values.firstWhere((e) => e.name == name,
          orElse: () => AccountType.other);
}

/// How the lender computes interest. The same headline rate costs very
/// different amounts depending on this.
enum InterestMethod {
  /// ลดต้นลดดอก: interest each month = outstanding balance × monthly rate.
  reducing('ลดต้นลดดอก'),

  /// อัตราคงที่: interest each month = original principal × monthly rate.
  flat('คงที่ (flat rate)');

  const InterestMethod(this.label);
  final String label;

  static InterestMethod fromName(String? name) =>
      InterestMethod.values.firstWhere((e) => e.name == name,
          orElse: () => InterestMethod.reducing);
}

enum PaymentType {
  minimum('จ่ายขั้นต่ำ'),
  full('จ่ายเต็มยอด'),
  extra('โปะเพิ่ม'),
  installment('ค่าผ่อนงวดปกติ'),
  other('อื่นๆ');

  const PaymentType(this.label);
  final String label;

  static PaymentType fromName(String? name) =>
      PaymentType.values.firstWhere((e) => e.name == name,
          orElse: () => PaymentType.other);
}

/// What to do with an installment plan after an extra prepayment.
enum PrepaymentMode {
  reducePayment('ลดค่าผ่อนต่อเดือน (จำนวนงวดเท่าเดิม)'),
  reduceTerm('ผ่อนเท่าเดิม แต่ปิดเร็วขึ้น');

  const PrepaymentMode(this.label);
  final String label;

  static PrepaymentMode? fromName(String? name) {
    for (final m in PrepaymentMode.values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

enum PaymentSource {
  manual('กรอกเอง'),
  sms('SMS'),
  email('อีเมล'),

  /// Recorded by a recurring charge (e.g. Netflix every month).
  recurring('รายการหักประจำ');

  const PaymentSource(this.label);
  final String label;

  static PaymentSource fromName(String? name) =>
      PaymentSource.values.firstWhere((e) => e.name == name,
          orElse: () => PaymentSource.manual);
}

/// How often a recurring card charge repeats.
enum RecurrenceInterval {
  monthly('ทุกเดือน', 1),
  yearly('ทุกปี', 12);

  const RecurrenceInterval(this.label, this.months);
  final String label;
  final int months;

  static RecurrenceInterval fromName(String? name) =>
      RecurrenceInterval.values.firstWhere((e) => e.name == name,
          orElse: () => RecurrenceInterval.monthly);
}
