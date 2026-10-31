import 'dart:io';

import 'package:debt_tracker/data/sources/date_text_parser.dart';
import 'package:debt_tracker/data/sources/sms/sms_parser_config.dart';
import 'package:debt_tracker/data/sources/sms/sms_parser_service.dart';
import 'package:debt_tracker/data/sources/statement_source_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundled = SmsParserConfig.fromJsonString(File('assets/sms_patterns.json').readAsStringSync());
  final parser = SmsParserService(bundled);
  final received = DateTime(2026, 10, 31, 12);

  RawStatementMessage sms(String sender, String body) => RawStatementMessage(
        source: StatementSourceType.sms,
        sender: sender,
        body: body,
        receivedAt: received,
      );

  RawStatementMessage pasted(String body) => RawStatementMessage(
        source: StatementSourceType.pasted,
        sender: '',
        body: body,
        receivedAt: received,
      );

  group('date text', () {
    final ref = DateTime(2026, 10, 31);
    test('numeric with BE / CE years', () {
      expect(parseDateText('25/10/69', reference: ref), DateTime(2026, 10, 25));
      expect(parseDateText('25/10/2569', reference: ref), DateTime(2026, 10, 25));
      expect(parseDateText('25-10-2026', reference: ref), DateTime(2026, 10, 25));
      expect(parseDateText('05/11/26', reference: ref), DateTime(2026, 11, 5));
    });

    test('Thai and English month names', () {
      expect(parseDateText('5 พ.ย. 69', reference: ref), DateTime(2026, 11, 5));
      expect(parseDateText('5 พฤศจิกายน 2569', reference: ref), DateTime(2026, 11, 5));
      expect(parseDateText('5 Nov 2026', reference: ref), DateTime(2026, 11, 5));
      expect(parseDateText('๕ ม.ค. ๗๐', reference: ref), DateTime(2027, 1, 5));
    });

    test('missing year resolves near the reference date', () {
      expect(parseDateText('25/10', reference: ref), DateTime(2026, 10, 25));
      expect(parseDateText('5/1', reference: DateTime(2026, 12, 20)), DateTime(2027, 1, 5));
    });

    test('invalid dates', () {
      expect(parseDateText('31/02/2026', reference: ref), isNull);
      expect(parseDateText('hello', reference: ref), isNull);
    });
  });

  group('SmsParserService', () {
    test('statement with total, minimum, due date and card', () {
      final e = parser.parse(sms('KTC',
          'KTC: ยอดเรียกเก็บบัตร x1234 รอบ 10/10/69 จำนวน 15,230.50 บ. ขั้นต่ำ 1,523.05 บ. ครบกำหนดชำระ 25/10/69'))!;
      expect(e.kind, StatementEventKind.statement);
      expect(e.bankId, 'ktc');
      expect(e.amount, 15230.50);
      expect(e.minimumDue, 1523.05);
      expect(e.dueDate, DateTime(2026, 10, 25));
      expect(e.cardLast4, '1234');
      expect(e.occurredAt, DateTime(2026, 10, 10));
    });

    test('payment received', () {
      final e = parser.parse(sms('KBank', 'ได้รับชำระเงิน 5,000.00 บาท บัตรเครดิต XX5678 วันที่ 20/10/2026 ขอบคุณค่ะ'))!;
      expect(e.kind, StatementEventKind.payment);
      expect(e.bankId, 'kbank');
      expect(e.amount, 5000);
      expect(e.cardLast4, '5678');
      expect(e.occurredAt, DateTime(2026, 10, 20));
    });

    test('card digits next to a keyword are not taken as the amount', () {
      final e = parser.parse(sms('KTC', 'ได้รับชำระค่าบัตร x1234 จำนวน 5,000 บาท ขอบคุณค่ะ'))!;
      expect(e.amount, 5000);
      expect(e.cardLast4, '1234');
    });

    test('spending', () {
      final e = parser.parse(sms('SCB', 'บัตร *9012 ใช้จ่าย 1,250.00 บาท ที่ TOPS 31/10/69 19:20'))!;
      expect(e.kind, StatementEventKind.spending);
      expect(e.bankId, 'scb');
      expect(e.amount, 1250);
      expect(e.cardLast4, '9012');
      expect(e.occurredAt, DateTime(2026, 10, 31));
    });

    test('pasted English statement identifies the bank from the text', () {
      final e = parser.parse(pasted(
          'UOB: Your statement balance THB 12,345.67, minimum payment THB 1,234.57 due 05/11/2026. Card ending 4321'))!;
      expect(e.kind, StatementEventKind.statement);
      expect(e.bankId, 'uob');
      expect(e.amount, 12345.67);
      expect(e.minimumDue, 1234.57);
      expect(e.dueDate, DateTime(2026, 11, 5));
      expect(e.cardLast4, '4321');
    });

    test('Thai month abbreviation in due date and Thai digits', () {
      final e = parser.parse(pasted('ยอดชำระเต็ม ๘,๙๐๐.๐๐ บาท ขั้นต่ำ 890.00 บาท กรุณาชำระภายใน 5 พ.ย. 69'))!;
      expect(e.amount, 8900);
      expect(e.minimumDue, 890);
      expect(e.dueDate, DateTime(2026, 11, 5));
    });

    test('OTP and unrelated messages are ignored', () {
      expect(parser.parse(sms('KTC', 'รหัส OTP 123456 สำหรับทำรายการ 1,000.00 บาท')), isNull);
      expect(parser.parse(sms('Friend', 'พรุ่งนี้เจอกันนะ')), isNull);
      expect(parser.parse(pasted('   ')), isNull);
    });

    test('e-mail messages are left to the e-mail parser', () {
      final m = RawStatementMessage(
        source: StatementSourceType.email,
        sender: 'statement@ktc.co.th',
        body: 'ยอดเรียกเก็บ 1,000.00 บาท',
        receivedAt: received,
      );
      expect(parser.canParse(m), isFalse);
      expect(parser.parse(m), isNull);
    });

    test('custom bank-specific patterns are tried before generic ones', () {
      final custom = SmsParserConfig.fromJson({
        'banks': [
          {'id': 'mybank', 'name': 'My Bank', 'senderIds': ['MYBANK']},
        ],
        'patterns': [
          {
            'id': 'mybank-bill',
            'bankId': 'mybank',
            'kind': 'statement',
            'trigger': r'BILL',
            'amount': r'BILL {AMOUNT}',
            'minimum': r'MIN {AMOUNT}',
            'dueDate': r'DUE {DATE}',
          },
        ],
      });
      final p = SmsParserService(bundled.merge(custom));
      final e = p.parse(sms('MYBANK', 'BILL 2500 MIN 250 DUE 15/11/69'))!;
      expect(e.patternId, 'mybank-bill');
      expect(e.bankName, 'My Bank');
      expect(e.amount, 2500);
      expect(e.minimumDue, 250);
      expect(e.dueDate, DateTime(2026, 11, 15));
      expect(p.isBankSender('mybank'), isTrue);
    });
  });
}
