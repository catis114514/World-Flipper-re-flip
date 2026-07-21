/// 定位 StarPoint CN 项目根目录。
///
/// launcher 作为 startpoint-cn-main 的子目录运行，根目录就是 launcher 的父目录。
/// 开发时从 `__dirname`(Dart 里用 Platform.script.path) 回推；编译后从可执行文件
/// 旁边的资源回推。为简化自用场景，这里支持两种来源：
///   1) 环境变量 STARPOINT_ROOT（最高优先）
///   2) launcher 的父目录
import 'dart:io';
import 'package:path/path.dart' as p;

class Paths {
  Paths._();

  /// StarPoint CN 项目根目录（launcher 的父目录）。
  static late final String root;

  static void init() {
    final env = Platform.environment['STARPOINT_ROOT'];
    if (env != null && env.isNotEmpty && Directory(env).existsSync()) {
      root = p.normalize(env);
      return;
    }
    // launcher/lib/... → 回退到当前工作目录的上两级。
    // 运行时 flutter run 的 cwd 是 launcher/，所以父目录就是根。
    final scriptDir = p.dirname(Platform.script.toFilePath());
    // scriptDir 在编译后指向 launcher/，回退两级到根。
    // 但更稳妥：尝试几个候选位置。
    final candidates = <String>[
      p.dirname(Directory.current.path), // launcher/ 的父目录
      p.dirname(p.dirname(scriptDir)),
    ];
    for (final c in candidates) {
      final envFile = p.join(c, '.env');
      final pkgFile = p.join(c, 'package.json');
      if (File(envFile).existsSync() || File(pkgFile).existsSync()) {
        root = p.normalize(c);
        return;
      }
    }
    // 兜底：用父目录。
    root = p.normalize(p.dirname(Directory.current.path));
  }

  static String get envFile => p.join(root, '.env');
  static String get envExample => p.join(root, '.env.example');
  static String get outDir => p.join(root, 'out');
  static String get cnServerJs => p.join(outDir, 'cn-server.js');
  static String get mitmproxyDir => p.join(root, '.mitmproxy');
  static String get mitmRedirectScript => p.join(root, 'scripts', 'mitm-redirect-traffic.py');
  static String get databaseDir => p.join(root, '.database');
  static String get dbFile => p.join(databaseDir, 'wdfp_data.db');

  /// 服务器监听地址（从 .env 读，带默认值）。
  static String webPanelUrl(String host, int port) =>
      'http://$host:$port/';
}
