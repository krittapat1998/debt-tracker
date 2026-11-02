package com.krittapat.debt_tracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// A FragmentActivity so local_auth can show the biometric prompt.
class MainActivity : FlutterFragmentActivity(), SmsPermissionHost {
    private var pendingPermissionResult: ((Boolean) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SmsBridge.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger, this)
    }

    override fun smsPermissionStatus(): String {
        if (hasSmsPermission()) return "granted"
        val askedBefore = getPreferences(MODE_PRIVATE).getBoolean(KEY_ASKED, false)
        // After a denial with "don't ask again" Android stops showing the
        // rationale and silently refuses: the user must use Settings.
        return if (askedBefore && !shouldShowRequestPermissionRationale(Manifest.permission.READ_SMS)) {
            "permanentlyDenied"
        } else {
            "denied"
        }
    }

    override fun requestSmsPermission(onResult: (Boolean) -> Unit) {
        if (hasSmsPermission()) {
            onResult(true)
            return
        }
        pendingPermissionResult = onResult
        getPreferences(MODE_PRIVATE).edit().putBoolean(KEY_ASKED, true).apply()
        requestPermissions(SMS_PERMISSIONS, REQUEST_SMS)
    }

    override fun openAppSettings() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_SMS) return
        val granted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.invoke(granted)
        pendingPermissionResult = null
    }

    private fun hasSmsPermission() = SMS_PERMISSIONS.all {
        checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val REQUEST_SMS = 7001
        private const val KEY_ASKED = "sms_permission_asked"
        private val SMS_PERMISSIONS = arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS)
    }
}
