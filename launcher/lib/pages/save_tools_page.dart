import 'package:flutter/material.dart';
import '../services/save_tools.dart';
import '../services/server_manager.dart';

class SaveToolsPage extends StatefulWidget {
  final ServerManager server;
  const SaveToolsPage({super.key, required this.server});
  @override
  State<SaveToolsPage> createState() => _SaveToolsPageState();
}

class _SaveToolsPageState extends State<SaveToolsPage> {
  List<Map<String, dynamic>> _players = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final players = await SaveTools.listPlayers();
      if (mounted) setState(() => _players = players);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addStones(int playerId, String name) async {
    final amount = await _showAmountDialog('给 $name 发免费石', '数量', defaultValue: 100000);
    if (amount == null) return;
    await SaveTools.addFreeVmoney(playerId, amount);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已给 $name +$amount 免费石')));
    }
  }

  Future<void> _setStones(int playerId, String name) async {
    final amount = await _showAmountDialog('设置 $name 的免费石', '直接设为', defaultValue: 999999);
    if (amount == null) return;
    await SaveTools.setFreeVmoney(playerId, amount);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已设 $name 免费石 = $amount')));
    }
  }

  Future<void> _diagUnlock(int playerId, String name) async {
    setState(() => _loading = true);
    try {
      final report = await SaveTools.tryUnlockUnison(playerId);
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('辅助位解锁诊断 - $name'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Text(report,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('诊断失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<int?> _showAmountDialog(String title, String label, {int defaultValue = 0}) {
    final ctrl = TextEditingController(text: defaultValue.toString());
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              Navigator.pop(context, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('存档工具', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
              onPressed: _loading ? null : _refresh,
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '改存档前建议先停止服务器，或改完后让玩家重新登录（/load）。'
                  '服务器运行中改存档有数据不一致风险。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error, color: Colors.red),
                title: const Text('读取存档失败'),
                subtitle: Text(_error!),
              ),
            )
          else if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _players.length,
                itemBuilder: (_, i) {
                  final p = _players[i];
                  final id = p['id'] as int;
                  final name = p['name'] as String? ?? '无名';
                  final stones = p['free_vmoney'] as int? ?? 0;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(name),
                      subtitle: Text('ID: $id · 免费石: $stones'),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (v) {
                          switch (v) {
                            case 'add':
                              _addStones(id, name);
                              break;
                            case 'set':
                              _setStones(id, name);
                              break;
                            case 'unlock':
                              _diagUnlock(id, name);
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'add', child: ListTile(
                            leading: Icon(Icons.add_circle), title: Text('发免费石 (+)'))),
                          const PopupMenuItem(value: 'set', child: ListTile(
                            leading: Icon(Icons.edit), title: Text('设置免费石 (=)'))),
                          const PopupMenuItem(value: 'unlock', child: ListTile(
                            leading: Icon(Icons.lock_open), title: Text('辅助位诊断'))),
                        ],
                      ),
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
