import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/formatters.dart';
import '../../domain/models/enums.dart';
import '../db/app_database.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Full JSON backup (optionally password-encrypted with AES-256-GCM, key
/// from PBKDF2-HMAC-SHA256) and human-readable CSV export.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  static const format = 'debt_tracker_backup';
  static const encryptedFormat = 'debt_tracker_backup_encrypted';
  static const _iterations = 120000;

  Future<Map<String, List<Map<String, Object?>>>> _dump() async => {
        for (final t in AppDatabase.tables) t: await _db.db.query(t),
      };

  Future<String> exportJson({String? password}) async {
    final plain = jsonEncode({
      'format': format,
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': await _dump(),
    });
    if (password == null || password.isEmpty) return plain;
    return Isolate.run(() => _encrypt(plain, password));
  }

  static bool isEncrypted(String content) {
    try {
      final j = jsonDecode(content);
      return j is Map && j['format'] == encryptedFormat;
    } catch (_) {
      return false;
    }
  }

  /// Replaces every table with the backup content. Returns row counts.
  Future<Map<String, int>> importJson(String content, {String? password}) async {
    Map<String, Object?> root;
    try {
      root = (jsonDecode(content) as Map).cast<String, Object?>();
    } catch (_) {
      throw BackupException('ไฟล์ไม่ใช่ JSON ที่ถูกต้อง');
    }
    if (root['format'] == encryptedFormat) {
      if (password == null || password.isEmpty) throw BackupException('ไฟล์นี้เข้ารหัสไว้ กรุณาใส่รหัสผ่าน');
      final decrypted = await Isolate.run(() => _decrypt(root, password));
      root = (jsonDecode(decrypted) as Map).cast<String, Object?>();
    }
    if (root['format'] != format) throw BackupException('ไม่ใช่ไฟล์สำรองข้อมูลของ Debt Tracker');
    final data = (root['data'] as Map).cast<String, Object?>();
    final counts = <String, int>{};
    await _db.db.transaction((txn) async {
      // Children first so foreign keys never block the wipe.
      for (final t in AppDatabase.tables.reversed) {
        await txn.delete(t);
      }
      for (final t in AppDatabase.tables) {
        final rows = (data[t] as List? ?? const []);
        for (final r in rows) {
          await txn.insert(t, (r as Map).cast<String, Object?>());
        }
        counts[t] = rows.length;
      }
    });
    return counts;
  }

  static Future<String> _encrypt(String plain, String password) async {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _deriveKey(password, salt, _iterations);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(plain), secretKey: key);
    return jsonEncode({
      'format': encryptedFormat,
      'version': 1,
      'kdf': {'name': 'pbkdf2-hmac-sha256', 'iterations': _iterations, 'salt': base64Encode(salt)},
      'cipher': {'name': 'aes-256-gcm', 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes)},
      'ciphertext': base64Encode(box.cipherText),
    });
  }

  static Future<String> _decrypt(Map<String, Object?> envelope, String password) async {
    final kdf = (envelope['kdf'] as Map).cast<String, Object?>();
    final cipher = (envelope['cipher'] as Map).cast<String, Object?>();
    final key = await _deriveKey(
      password,
      base64Decode(kdf['salt'] as String),
      (kdf['iterations'] as num).toInt(),
    );
    final box = SecretBox(
      base64Decode(envelope['ciphertext'] as String),
      nonce: base64Decode(cipher['nonce'] as String),
      mac: Mac(base64Decode(cipher['mac'] as String)),
    );
    try {
      return utf8.decode(await AesGcm.with256bits().decrypt(box, secretKey: key));
    } on SecretBoxAuthenticationError {
      throw BackupException('รหัสผ่านไม่ถูกต้อง หรือไฟล์ถูกแก้ไข');
    }
  }

  static Future<SecretKey> _deriveKey(String password, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  /// CSV files (UTF-8 with BOM so Excel shows Thai correctly).
  Future<Map<String, String>> exportCsv() async {
    final dump = await _dump();
    final names = {
      for (final a in dump['accounts']!) a['id']: a['name'],
    };
    final planNames = {
      for (final p in dump['installment_plans']!) p['id']: p['name'],
    };
    final lineNames = {
      for (final l in dump['credit_lines']!) l['id']: l['name'],
    };
    final out = <String, String>{};
    for (final t in ['accounts', 'credit_lines', 'installment_plans']) {
      out['$t.csv'] = _toCsv(dump[t]!);
    }
    out['payments.csv'] = _toCsv([
      for (final p in dump['payments']!)
        {
          'date': p['date'],
          'account': names[p['account_id']] ?? '',
          'plan': planNames[p['plan_id']] ?? '',
          'amount': p['amount'],
          'type': PaymentType.fromName(p['type'] as String?).label,
          'source': PaymentSource.fromName(p['source'] as String?).label,
          'note': p['note'] ?? '',
          'date_th': fmtDate(DateTime.parse(p['date'] as String)),
        },
    ]);
    out['spendings.csv'] = _toCsv([
      for (final s in dump['spendings']!)
        {
          'date': s['date'],
          'account': names[s['account_id']] ?? '',
          'credit_line': lineNames[s['credit_line_id']] ?? '',
          'amount': s['amount'],
          'note': s['note'] ?? '',
          'source': PaymentSource.fromName(s['source'] as String?).label,
          'date_th': fmtDate(DateTime.parse(s['date'] as String)),
        },
    ]);
    return out;
  }

  static String _toCsv(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return '﻿';
    final headers = rows.first.keys.toList();
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer('﻿')..writeln(headers.map(cell).join(','));
    for (final r in rows) {
      b.writeln(headers.map((h) => cell(r[h])).join(','));
    }
    return b.toString();
  }
}
