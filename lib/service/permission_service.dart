import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static const _platform = MethodChannel('com.example.message_me/settings');

  // ✅ Request all basic permissions on app start
  static Future<void> request() async {
    await Permission.phone.request();
    await Permission.sms.request();
    await Permission.contacts.request();
    await Permission.notification.request();
    await Permission.ignoreBatteryOptimizations.request();

    // Check permanently denied
    if (await Permission.phone.isPermanentlyDenied ||
        await Permission.sms.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  // ✅ Check all permission statuses at once
  static Future<Map<String, bool>> checkAll() async {
    final phone = await Permission.phone.isGranted;
    final sms = await Permission.sms.isGranted;
    final notification = await Permission.notification.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final overlay = await hasOverlayPermission();
    final contacts = await Permission.contacts.isGranted;

    return {
      'phone': phone,
      'sms': sms,
      'notification': notification,
      'battery': battery,
      'overlay': overlay,
      'contacts': contacts,
    };
  }

  // ✅ Check if overlay permission is granted
  static Future<bool> hasOverlayPermission() async {
    try {
      final result = await _platform.invokeMethod('checkOverlayPermission');
      return result == true;
    } catch (_) {
      return true; // assume granted if can't check
    }
  }

  // ✅ Open overlay permission settings
  static Future<void> requestOverlayPermission() async {
    try {
      await _platform.invokeMethod('requestOverlayPermission');
    } catch (_) {
      await openAppSettings();
    }
  }

  // ✅ Open battery optimization settings
  static Future<void> requestBatteryOptimization() async {
    try {
      await _platform.invokeMethod('openBatterySettings');
    } catch (_) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  // ✅ Open manufacturer-specific battery settings
  static Future<void> openManufacturerSettings(
    BuildContext context,
    String manufacturer,
  ) async {
    final m = manufacturer.toLowerCase();
    bool opened = false;

    try {
      if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
        opened = await _tryIntent(
          'com.miui.securitycenter',
          'com.miui.permcenter.autostart.AutoStartManagementActivity',
        );
        if (!opened) {
          opened = await _tryIntent('com.miui.securitycenter', '');
        }
      } else if (m.contains('oppo') || m.contains('realme')) {
        opened = await _tryIntent(
          'com.coloros.safecenter',
          'com.coloros.powermanager.stardardmode.PowerUsageModelActivity',
        );
        if (!opened) {
          opened = await _tryIntent('com.oppo.safe', '');
        }
      } else if (m.contains('vivo')) {
        opened = await _tryIntent(
          'com.vivo.permissionmanager',
          'com.vivo.permissionmanager.activity.PurviewTabActivity',
        );
        if (!opened) {
          opened = await _tryIntent('com.iqoo.secure', '');
        }
      } else if (m.contains('huawei') || m.contains('honor')) {
        opened = await _tryIntent(
          'com.huawei.systemmanager',
          'com.huawei.systemmanager.startemup.bootmanager.'
              'StartupNormalAppListActivity',
        );
        if (!opened) {
          opened = await _tryIntent('com.huawei.systemmanager', '');
        }
      } else if (m.contains('samsung')) {
        opened = await _tryIntent(
          'com.samsung.android.lool',
          'com.samsung.android.lool.feature.battery.ui.BatteryActivity',
        );
        if (!opened) {
          await requestBatteryOptimization();
          opened = true;
        }
      } else if (m.contains('oneplus')) {
        opened = await _tryIntent('com.oneplus.security', '');
      }
    } catch (_) {}

    if (!opened) {
      await requestBatteryOptimization();
    }
  }

  static Future<bool> _tryIntent(String package, String activity) async {
    try {
      final result = await _platform.invokeMethod('openIntent', {
        'package': package,
        'activity': activity,
      });
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // ✅ Clear dedup keys — useful for testing
  static Future<void> clearDedupKeys() async {
    try {
      await _platform.invokeMethod('clearDedupKeys');
    } catch (_) {}
  }
}
