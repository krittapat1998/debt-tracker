import 'package:local_auth/local_auth.dart';

/// Face ID / fingerprint, falling back to the phone's passcode, for the
/// app lock.
class AppLockService {
  final _auth = LocalAuthentication();

  /// The phone can check who is holding it (biometrics or a passcode).
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Asks for Face ID (or the passcode); false when cancelled or failed.
  Future<bool> unlock(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }
}
