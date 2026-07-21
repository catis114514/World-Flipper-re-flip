/// 服务器进程托管 + 实时日志。
///
/// 用 dart:io Process spawn `node out/cn-server.js`，捕获 stdout/stderr 实时推给 UI。
/// 服务器用 --env-file=.env 加载环境变量（对齐项目 npm run dev:cn 的行为）。
import 'dart:async';
import 'dart:io';
import 'paths.dart';
import 'env_config.dart';

enum ServerState { stopped, starting, running, error }

class LogEntry {
  final DateTime time;
  final String line;
  final bool isError;
  LogEntry(this.line, {this.isError = false}) : time = DateTime.now();
}

class ServerManager {
  Process? _process;
  ServerState _state = ServerState.stopped;
  final _logController = StreamController<LogEntry>.broadcast();
  final _stateController = StreamController<ServerState>.broadcast();

  Stream<LogEntry> get logs => _logController.stream;
  Stream<ServerState> get state => _stateController.stream;
  ServerState get currentState => _state;

  String get listenHost =>
      EnvConfig.get('CN_LISTEN_HOST', '127.0.0.1');
  int get listenPort =>
      int.tryParse(EnvConfig.get('CN_LISTEN_PORT', '8001')) ?? 8001;

  void _setState(ServerState s) {
    _state = s;
    _stateController.add(s);
  }

  /// 启动 CN 服务器。build=false 时跳过 tsc（假设已 build 过）。
  Future<void> start({bool build = false}) async {
    if (_process != null) {
      _log('服务器已在运行', isError: true);
      return;
    }
    _setState(ServerState.starting);
    _log('准备启动 CN 服务器...');

    // 确认 node 和编译产物存在
    final nodeExe = await _which('node');
    if (nodeExe == null) {
      _log('未找到 node，请先安装 Node.js >= 20', isError: true);
      _setState(ServerState.error);
      return;
    }
    final serverJs = File(Paths.cnServerJs);
    if (!serverJs.existsSync()) {
      _log('未找到 out/cn-server.js，请先执行 npm run build', isError: true);
      _setState(ServerState.error);
      return;
    }

    if (build) {
      _log('执行 npm run build (tsc + css)...');
      final buildResult = await Process.run(
        nodeExe,
        ['node_modules/npm/bin/npm-cli.js', 'run', 'build'],
        workingDirectory: Paths.root,
        runInShell: true,
      );
      if (buildResult.exitCode != 0) {
        _log('构建失败:\n${buildResult.stderr}', isError: true);
        _setState(ServerState.error);
        return;
      }
      _log('构建完成');
    }

    try {
      _process = await Process.start(
        nodeExe,
        ['--env-file=.env', 'out/cn-server.js'],
        workingDirectory: Paths.root,
        runInShell: false,
      );
      _setState(ServerState.running);
      _log('服务器进程已启动 (pid=${_process!.pid})');

      _process!.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) => _log(line));
      _process!.stderr
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) => _log(line, isError: true));

      final exitCode = await _process!.exitCode;
      _log('服务器进程退出 (code=$exitCode)');
      _process = null;
      _setState(ServerState.stopped);
    } catch (e) {
      _log('启动异常: $e', isError: true);
      _setState(ServerState.error);
    }
  }

  /// 优雅停止：Windows 上没有 SIGTERM，用 taskkill /F 强制结束进程树。
  Future<void> stop() async {
    final p = _process;
    if (p == null) {
      _setState(ServerState.stopped);
      return;
    }
    _log('正在停止服务器...');
    try {
      // Windows: 杀掉整个进程树（node 可能 fork 了 session server）
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${p.pid}', '/T', '/F']);
      } else {
        p.kill(ProcessSignal.sigterm);
      }
    } catch (e) {
      _log('停止异常: $e', isError: true);
    }
    _process = null;
    _setState(ServerState.stopped);
  }

  /// 重启。
  Future<void> restart({bool build = false}) async {
    await stop();
    await Future.delayed(const Duration(milliseconds: 500));
    await start(build: build);
  }

  void _log(String msg, {bool isError = false}) {
    _logController.add(LogEntry(msg, isError: isError));
  }

  /// 模拟 `which`/`where`，返回可执行文件路径。
  Future<String?> _which(String exe) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, [exe], runInShell: true);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) return out.split('\n').first.trim();
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    stop();
    _logController.close();
    _stateController.close();
  }
}
