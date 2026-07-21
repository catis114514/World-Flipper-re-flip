/// 环境检测：检查启动器和 patch 依赖的外部工具是否就位。
///
/// node / mitmproxy：启动器核心依赖
/// java / ffdec / zipalign / apksigner：patch 全链路依赖
/// 检测策略：先查项目内固定位置，再查 PATH。
import 'dart:io';
import 'package:path/path.dart' as p;
import 'paths.dart';

class ToolStatus {
  final String name;
  final String? path; // null = 未找到
  final String help;  // 缺失时给用户的提示
  bool get ok => path != null;
  ToolStatus(this.name, this.path, this.help);
}

class EnvCheck {
  /// 检测所有工具，返回列表。
  static Future<List<ToolStatus>> checkAll() async {
    return [
      await _checkNode(),
      await _checkMitmproxy(),
      await _checkJava(),
      await _checkFfdec(),
      await _checkZipalign(),
      await _checkApksigner(),
    ];
  }

  static Future<ToolStatus> _which(String exe, {required String help}) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final r = await Process.run(cmd, [exe], runInShell: true);
      if (r.exitCode == 0) {
        final out = (r.stdout as String).trim();
        if (out.isNotEmpty) {
          return ToolStatus(exe, out.split('\n').first.trim(), help);
        }
      }
    } catch (_) {}
    return ToolStatus(exe, null, help);
  }

  static Future<ToolStatus> _checkNode() => _which('node',
      help: '安装 Node.js >= 20：https://nodejs.org/');

  static Future<ToolStatus> _checkMitmproxy() async {
    // 项目内 .mitmproxy/mitmweb.exe
    final local = Platform.isWindows
        ? p.join(Paths.mitmproxyDir, 'mitmweb.exe')
        : p.join(Paths.mitmproxyDir, 'mitmweb');
    if (File(local).existsSync()) {
      return ToolStatus('mitmproxy', local, '');
    }
    return _which('mitmweb',
        help: '把 mitmweb 放进 .mitmproxy/ 或装到 PATH：https://mitmproxy.org/');
  }

  static Future<ToolStatus> _checkJava() => _which('java',
      help: '装 JDK（FFDec 运行需要）：https://adoptium.net/');

  static Future<ToolStatus> _checkFfdec() async {
    // 常见位置：项目根 ffdec/ 或用户配置
    final candidates = [
      p.join(Paths.root, 'ffdec', 'ffdec.jar'),
      p.join(Paths.root, 'ffdec.jar'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return ToolStatus('ffdec', c, '');
    }
    // PATH 里可能有 ffdec 命令
    final pathBased = await _which(
        Platform.isWindows ? 'ffdec' : 'ffdec',
        help: '下载 FFDec 并解压到 ffdec/：https://github.com/jindrapetrik/jpexs-decompiler/releases');
    if (pathBased.ok) return pathBased;
    return ToolStatus('ffdec', null,
        '下载 FFDec 并解压到 ffdec/：https://github.com/jindrapetrik/jpexs-decompiler/releases');
  }

  static Future<ToolStatus> _checkZipalign() => _which('zipalign',
      help: '装 Android SDK build-tools（含 zipalign）：https://developer.android.com/studio');

  static Future<ToolStatus> _checkApksigner() => _which('apksigner',
      help: '装 Android SDK build-tools（含 apksigner）：https://developer.android.com/studio');
}
