import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/store.dart';
import '../l10n/i18n.dart';

/// WebDAV 云备份：兼容坚果云、群晖、Nextcloud 等任意 WebDAV 服务。
/// 配置仅存本机 start_prefs；功能默认关闭，开启后仅在用户手动点备份/恢复时联网，
/// 传输内容为本地数据导出的 JSON 文件，不收集其他任何信息。
class WebDav {
  WebDav._();

  static bool get on => StartStore.I.prefBool('wd_on', false);
  static String get url => StartStore.I.prefStr('wd_url');
  static String get user => StartStore.I.prefStr('wd_user');
  static String get pass => StartStore.I.prefStr('wd_pass');

  static bool get ready =>
      on && url.trim().isNotEmpty && user.trim().isNotEmpty && pass.trim().isNotEmpty;

  static Future<void> setOn(bool v) => StartStore.I.setPref('wd_on', v);
  static Future<void> setUrl(String v) => StartStore.I.setPref('wd_url', v.trim());
  static Future<void> setUser(String v) => StartStore.I.setPref('wd_user', v.trim());
  static Future<void> setPass(String v) => StartStore.I.setPref('wd_pass', v.trim());

  static String _auth() =>
      'Basic ${base64Encode(utf8.encode('${user.trim()}:${pass.trim()}'))}';

  static Uri _uri([String file = '']) {
    var base = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (file.isNotEmpty) base = '$base/${Uri.encodeComponent(file)}';
    return Uri.parse(base);
  }

  static Map<String, String> get _headers => {
        'Authorization': _auth(),
      };

  /// 连通性验证：PROPFIND 根目录，返回成功与否。
  static Future<void> ping() async {
    final req = http.Request('PROPFIND', _uri())
      ..headers.addAll(_headers)
      ..headers['Depth'] = '0'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0"?><propfind xmlns="DAV:"><prop>'
          '<displayname/></prop></propfind>';
    final resp = await http
        .Client()
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
  }

  /// 上传一份备份，返回备份文件名。
  static Future<String> backup() async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:T]'), '')
        .substring(0, 14);
    final name = 'qixu-backup-$stamp.json';
    final resp = await http
        .put(
          _uri(name),
          headers: {..._headers, 'Content-Type': 'application/json; charset=utf-8'},
          body: StartStore.I.exportJson(),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return name;
  }

  /// 列出云端备份文件名（旧→新）。PROPFIND Depth:1 后从 href 里提取。
  static Future<List<String>> list() async {
    final req = http.Request('PROPFIND', _uri())
      ..headers.addAll(_headers)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0"?><propfind xmlns="DAV:"><prop>'
          '<getcontentlength/></prop></propfind>';
    final resp = await http
        .Client()
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final names = RegExp(r'<(?:[A-Za-z]+:)?href[^>]*>([^<]+)</(?:[A-Za-z]+:)?href>')
        .allMatches(resp.body)
        .map((m) => Uri.decodeComponent(m.group(1)!).split('/').last)
        .where((n) => n.startsWith('qixu-backup-') && n.endsWith('.json'))
        .toSet()
        .toList()
      ..sort();
    return names;
  }

  /// 下载最新一份备份内容。
  static Future<String> fetchLatest() async {
    final names = await list();
    if (names.isEmpty) throw Exception(tr('云端没有备份'));
    final resp = await http
        .get(_uri(names.last), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
  }
}
