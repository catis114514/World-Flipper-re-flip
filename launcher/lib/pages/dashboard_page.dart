import 'dart:async';
import 'package:flutter/material.dart';
import '../services/server_manager.dart';
import '../services/api_client.dart';

class DashboardPage extends StatefulWidget {
  final ServerManager server;
  const DashboardPage({super.key, required this.server});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _logs = <LogEntry>[];
  final _scrollController = ScrollController();
  StreamSubscription? _logSub;
  StreamSubscription? _stateSub;
  ServerState _state = ServerState.stopped;
  bool _serverOnline = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _state = widget.server.currentState;
    _logSub = widget.server.logs.listen((entry) {
      setState(() {
        _logs.add(entry);
        // 只保留最近 2000 行，避免内存爆
        if (_logs.length > 2000) _logs.removeRange(0, _logs.length - 2000);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
    _stateSub = widget.server.state.listen((s) => setState(() => _state = s));
    _pollServerStatus();
  }

  void _pollServerStatus() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final online = await ApiClient.isOnline();
      if (mounted && online != _serverOnline) {
        setState(() => _serverOnline = online);
      }
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _stateSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(),
          const SizedBox(height: 16),
          Expanded(child: _buildLogPanel()),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusText = switch (_state) {
      ServerState.stopped => '已停止',
      ServerState.starting => '启动中...',
      ServerState.running => _serverOnline ? '运行中 (在线)' : '运行中 (检测中)',
      ServerState.error => '错误',
    };
    final statusColor = switch (_state) {
      ServerState.running => _serverOnline ? Colors.green : Colors.orange,
      ServerState.starting => Colors.orange,
      ServerState.stopped => Colors.grey,
      ServerState.error => Colors.red,
    };
    final running = _state == ServerState.running || _state == ServerState.starting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.circle, color: statusColor, size: 14),
              const SizedBox(width: 8),
              Text(statusText, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (running) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重启'),
                  onPressed: () => widget.server.restart(),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                  onPressed: () => widget.server.stop(),
                ),
              ] else ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('启动 (已构建)'),
                  onPressed: () => widget.server.start(),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.build),
                  label: const Text('构建并启动'),
                  onPressed: () => widget.server.start(build: true),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              const Icon(Icons.terminal, size: 18),
              const SizedBox(width: 8),
              Text('服务器日志', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空'),
                onPressed: () => setState(() => _logs.clear()),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (_, i) {
                final e = _logs[i];
                return Text(
                  e.line,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    color: e.isError ? Colors.red.shade700 : Colors.black87,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
