import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VersionService {
  static final _client = Supabase.instance.client;

  static Future<PackageInfo> getCurrentPackageInfo() async {
    return await PackageInfo.fromPlatform();
  }

  static Future<int?> getLatestBuildNumber() async {
    try {
      final data = await _client
          .from('app_version')
          .select('build_number')
          .limit(1)
          .single();
      return (data['build_number'] as num).toInt();
    } catch (e) {
      print('Version check error: $e');
      return null;
    }
  }

  static Future<bool> isUpToDate() async {
    final info = await getCurrentPackageInfo();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    final latestBuild = await getLatestBuildNumber();
    if (latestBuild == null) return true;
    return currentBuild >= latestBuild;
  }
}
