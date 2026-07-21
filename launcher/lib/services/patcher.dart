/// 客户端补丁全链路：FFDec 反编译 → 改两文件 → 回封 → zipalign → apksigner 签名。
///
/// 对齐 client-patch/apply.sh 的语义：
///   1. DevConfig.as: sdkDummy = false → true（免登录）
///   2. DevConfig_gf_android.as: 域名 → host:port，https → http（重定向到本服）
/// FFDec CLI 语法（来自官方 wiki Commandline-arguments）：
///   -export script <outdir> <swf>     导出 AS3 脚本
///   -import script <swf> <outdir>     把脚本导回 SWF
/// 注意：FFDec 的 -import 是覆盖整个 SWF 中对应 P-Code，需要先 -export 拿到文件再改再 -import。
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'paths.dart';
import 'env_check.dart';
import 'env_config.dart';

class PatchStep {
  final String name;
  final String detail;
  final bool success;
  PatchStep(this.name, this.detail, {required this.success});
}

class Patcher {
  final _stepController = StreamController<PatchStep>.broadcast();
  Stream<PatchStep> get steps => _stepController.stream;

  void _step(String name, String detail, {required bool success}) {
    _stepController.add(PatchStep(name, detail, success: success));
  }

  /// 解析 ffdec.jar 路径。
  Future<String?> _findFfdec() async {
    final candidates = [
      p.join(Paths.root, 'ffdec', 'ffdec.jar'),
      p.join(Paths.root, 'ffdec.jar'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  /// 执行全链路补丁。
  /// [apkPath] 源 APK；[apiHost] 形如 192.168.1.10:8001；[keystore] 签名密钥库；
  /// [ksPass]/[ksAlias] 密钥库密码/别名。
  /// 返回输出 APK 路径，失败返回 null。
  Future<String?> patchApk({
    required String apkPath,
    required String apiHost,
    required String keystore,
    required String ksPass,
    required String ksAlias,
  }) async {
    // 0. 环境校验
    final java = (await EnvCheck.checkAll())
        .where((t) => t.name == 'java' && t.ok)
        .firstOrNull;
    if (java == null) {
      _step('环境检查', '未找到 java，无法运行 FFDec', success: false);
      return null;
    }
    final ffdecJar = await _findFfdec();
    if (ffdecJar == null) {
      _step('环境检查', '未找到 ffdec.jar，请放到 ffdec/ 目录', success: false);
      return null;
    }
    _step('环境检查', 'java=${java.path}\nffdec=$ffdecJar', success: true);

    final workDir = await _makeTempDir();
    final swfPath = p.join(workDir, 'main.swf');
    final scriptDir = p.join(workDir, 'scripts');

    try {
      // 1. 从 APK 提取主 SWF
      if (!await _extractMainSwf(apkPath, swfPath)) {
        _step('提取 SWF', '未能从 APK 中找到主 SWF (assets/bin/)', success: false);
        return null;
      }
      _step('提取 SWF', '主 SWF: $swfPath', success: true);

      // 2. FFDec 导出 AS3 脚本
      final exportOk = await _runFfdec(ffdecJar, java.path, workDir, [
        '-export', 'script', scriptDir, swfPath,
      ], 'FFDec 导出 AS3');
      if (!exportOk) return null;

      // 3. 定位并修改两个文件
      final devConfig = await _findFile(scriptDir, 'DevConfig.as', 'core');
      final gfConfig = await _findFile(scriptDir, 'DevConfig_gf_android.as', null);
      if (devConfig == null || gfConfig == null) {
        _step('定位文件', '未找到 DevConfig.as 或 DevConfig_gf_android.as', success: false);
        return null;
      }
      _modifyDevConfig(devConfig);
      _modifyGfConfig(gfConfig, apiHost);
      _step('修改 AS3', 'DevConfig.as (sdkDummy=true)\nDevConfig_gf_android.as (→ $apiHost, http)', success: true);

      // 4. FFDec 回封脚本到 SWF
      final importOk = await _runFfdec(ffdecJar, java.path, workDir, [
        '-import', 'script', scriptDir, swfPath,
      ], 'FFDec 回封');
      if (!importOk) return null;

      // 5. 把改后的 SWF 放回 APK
      final patchedApk = p.join(workDir, 'patched.apk');
      await _putSwfBack(apkPath, patchedApk, swfPath);
      _step('回填 SWF', patchedApk, success: true);

      // 6. zipalign
      final alignedApk = p.join(workDir, 'aligned.apk');
      final alignOk = await _runCmd('zipalign',
          ['-f', '-p', '4', patchedApk, alignedApk], 'zipalign 对齐');
      if (!alignOk) return null;

      // 7. apksigner 签名
      final signedApk = p.join(p.dirname(apkPath),
          '${p.basenameWithoutExtension(apkPath)}-patched.apk');
      final signOk = await _runCmd('apksigner', [
        'sign',
        '--ks', keystore,
        '--ks-pass', 'pass:$ksPass',
        '--ks-key-alias', ksAlias,
        '--out', signedApk,
        alignedApk,
      ], 'apksigner 签名');
      if (!signOk) return null;

      _step('完成', '输出: $signedApk', success: true);
      return signedApk;
    } catch (e) {
      _step('异常', '$e', success: false);
      return null;
    } finally {
      // 保留 workDir 以便排错；可改为自动清理
    }
  }

  Future<String> _makeTempDir() async {
    final dir = Directory(p.join(Paths.root, '.patch-work',
        DateTime.now().millisecondsSinceEpoch.toString()));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// 用 unzip 从 APK 解出主 SWF（AIR 应用在 assets/bin/*.swf）。
  Future<bool> _extractMainSwf(String apk, String swfOut) async {
    // 尝试常见位置
    final candidates = ['assets/bin/main.swf', 'assets/bin/Main.swf'];
    for (final entry in candidates) {
      final r = await Process.run(
        'java', ['-jar', await _findUnzipper(), apk, entry, swfOut],
        runInShell: true);
      if (r.exitCode == 0 && File(swfOut).existsSync()) return true;
    }
    return false;
  }

  Future<String> _findUnzipper() async => p.join(Paths.root, 'ffdec', 'ffdec.jar');

  /// 递归查找文件。
  Future<String?> _findFile(String dir, String name, String? pathContains) async {
    final result = <String>[];
    await for (final entity in Directory(dir).list(recursive: true)) {
      if (entity is File && p.basename(entity.path) == name) {
        if (pathContains == null || entity.path.contains(pathContains.replaceAll('/', p.separator))) {
          result.add(entity.path);
        }
      }
    }
    return result.isEmpty ? null : result.first;
  }

  void _modifyDevConfig(String path) {
    final content = File(path).readAsStringSync();
    final patched = content.replaceAll(
      'public static var sdkDummy:Boolean = false;',
      'public static var sdkDummy:Boolean = true;');
    File(path).writeAsStringSync(patched);
  }

  void _modifyGfConfig(String path, String apiHost) {
    var content = File(path).readAsStringSync();
    content = content.replaceAll(
      'shijtswygamegf.leiting.com', apiHost);
    content = content.replaceAll('"https"', '"http"');
    File(path).writeAsStringSync(content);
  }

  /// 把改后的 SWF 放回 APK（zip 覆盖）。
  Future<void> _putSwfBack(String srcApk, String dstApk, String swfPath) async {
    await File(srcApk).copy(dstApk);
    // 用 zip 更新条目（Windows 自带 tar 支持 zip）
    await Process.run('tar', ['-uf', dstApk,
      '-C', p.dirname(swfPath), p.basename(swfPath)], runInShell: true);
  }

  Future<bool> _runFfdec(String jar, String java, String workDir,
      List<String> args, String label) async {
    return _runCmd(java, ['-jar', jar, ...args], label, workDir: workDir);
  }

  Future<bool> _runCmd(String exe, List<String> args, String label,
      {String? workDir}) async {
    _step(label, '> ${[exe, ...args].join(' ')}', success: true);
    final r = await Process.run(exe, args,
        workingDirectory: workDir ?? Paths.root,
        runInShell: true);
    final out = (r.stdout as String).trim();
    final err = (r.stderr as String).trim();
    final ok = r.exitCode == 0;
    if (out.isNotEmpty) _step('$label (输出)', out, success: ok);
    if (err.isNotEmpty) _step('$label (stderr)', err, success: ok);
    if (!ok) _step(label, '退出码 ${r.exitCode}，失败', success: false);
    return ok;
  }

  void dispose() => _stepController.close();
}
