import 'dart:convert';

import 'package:http/http.dart' as http;

import '../channels/native.dart';

/// 检查应用更新：请求版本信息源，对比版本号。
/// 配置 [_url] 为你的 Gitee/GitHub releases API 地址。
class UpdateChecker {
  // Gitee: https://gitee.com/api/v5/repos/{owner}/{repo}/releases/latest
  // GitHub: https://api.github.com/repos/{owner}/{repo}/releases/latest
  static const _url =
      'https://gitee.com/api/v5/repos/dubwhr/astart/releases/latest';

  static String? _current;

  /// 当前版本号：PackageManager 实时读取（读取一次后缓存），自动跟随 build.gradle。
  static Future<String> current() async {
    if (_current != null) return _current!;
    _current = await Native.versionName() ?? '1';
    return _current!;
  }

  /// 返回 null=无更新或检查失败；非 null=有新版本（version + 下载地址）
  static Future<({String version, String url})?> check() async {
    try {
      final cur = await current();
      final resp = await http.get(Uri.parse(_url));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '')
          .toString()
          .replaceAll(RegExp(r'[^0-9.]'), '');
      if (tag.isEmpty) return null;
      if (_compare(tag, cur) > 0) {
        final assets = j['assets'] as List?;
        String dl = '';
        if (assets != null && assets.isNotEmpty) {
          dl = (assets.first as Map?)?['browser_download_url'] as String? ?? '';
        }
        // 发了版但没传附件时，兜底跳到 Releases 页面，避免下载无响应。
        if (dl.isEmpty) dl = 'https://gitee.com/dubwhr/astart/releases';
        return (version: tag, url: dl);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static int _compare(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final d =
          (pa.length > i ? pa[i] : 0) - (pb.length > i ? pb[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }
}
