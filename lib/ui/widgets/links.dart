import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

/// Places outside the app it points to.
abstract final class AppLinks {
  /// The developer's site. The domain decides where it lands, so the app never
  /// needs an update when that changes.
  static final developer = Uri.parse('https://kritdev.com');
}

/// Opens [url] in the browser, and says so when it can't.
Future<void> openLink(BuildContext context, Uri url) async {
  var opened = false;
  try {
    opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openLink $url: $e');
  }
  if (!opened && context.mounted) showSnack(context, 'เปิดลิงก์ไม่ได้ ลองพิมพ์ ${url.host} ในเบราว์เซอร์');
}
