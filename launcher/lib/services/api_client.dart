/// 调用 StarPoint CN 服务器的管理面板 API（只读）。
///
/// 对接现有的 /api/server、/api/player 等 Web API（见 src/routes/web_api/）。
/// 这些 API 是普通 JSON，不走 MsgPack 管线。
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env_config.dart';

class ApiClient {
  static String get _base {
    final host = EnvConfig.get('CN_LISTEN_HOST', '127.0.0.1');
    final port = EnvConfig.get('CN_LISTEN_PORT', '8001');
    return 'http://$host:$port';
  }

  /// 服务器是否在线（探测 currentTime 端点）。
  static Future<bool> isOnline() async {
    try {
      final r = await http
          .get(Uri.parse('$_base/api/server/currentTime'))
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取服务器时间。
  static Future<Map<String, dynamic>> getServerTime() async {
    final r = await http.get(Uri.parse('$_base/api/server/currentTime'));
    if (r.statusCode != 200) {
      throw Exception('服务器返回 ${r.statusCode}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// 获取玩家列表。
  static Future<List<dynamic>> getPlayers({int page = 0, int perPage = 25}) async {
    final r = await http.get(Uri.parse(
        '$_base/api/player?page=$page&perPage=$perPage'));
    if (r.statusCode != 200) {
      throw Exception('服务器返回 ${r.statusCode}');
    }
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// 获取玩家存档快照。
  static Future<Map<String, dynamic>?> getPlayerSave(int playerId) async {
    final r = await http.get(Uri.parse('$_base/api/player/save?id=$playerId'));
    if (r.statusCode != 200) return null;
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// 管理面板某页的完整 URL（用于"在浏览器打开"）。
  static String panelUrl(String path) => '$_base${path.startsWith('/') ? '' : '/'}$path';
}
