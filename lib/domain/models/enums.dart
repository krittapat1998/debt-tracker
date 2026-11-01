enum AccountType {
  creditCard('บัตรเครดิต', 'ยอดรูดบัตร'),
  cashCard('บัตรกดเงินสด', 'ยอดกดเงินสด'),
  personalLoan('สินเชื่อส่วนบุคคล', 'ยอดเบิกใช้'),
  other('อื่นๆ', 'ยอดใช้วงเงิน');

  const AccountType(this.label, this.revolvingLabel);
  final String label;

  /// Plain name for a sub-limit's balance outside installment plans.
  final String revolvingLabel;

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
  email('อีเมล');

  const PaymentSource(this.label);
  final String label;

  static PaymentSource fromName(String? name) =>
      PaymentSource.values.firstWhere((e) => e.name == name,
          orElse: () => PaymentSource.manual);
}
