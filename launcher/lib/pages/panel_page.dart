import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/server_manager.dart';
import '../services/api_client.dart';

class PanelPage extends StatefulWidget {
  final ServerManager server;
  const PanelPage({super.key, required this.server});
  @override
  State<PanelPage> createState() => _PanelPageState();
}

class _PanelPageState extends State<PanelPage> {
  Map<String, dynamic>? _serverTime;
  List<dynamic>? _players;
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final time = await ApiClient.getServerTime();
      final players = await ApiClient.getPlayers(perPage: 25);
      if (mounted) {
        setState(() {
          _serverTime = time;
          _players = players;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Uri url) async {
    await launchUrl(url);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('管理面板 (只读)', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
              onPressed: _loading ? null : _refresh,
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.open_in_browser),
              label: const Text('在浏览器打开'),
              onPressed: () => _open(Uri.parse(ApiClient.panelUrl('/'))),
            ),
          ]),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_error != null)
            _buildErrorCard()
          else
            Expanded(
              child: ListView(
                children: [
                  _buildTimeCard(),
                  const SizedBox(height: 16),
                  _buildPlayersCard(),
                  const SizedBox(height: 16),
                  _buildLinksCard(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            const Text('无法连接服务器', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            const Text('请先在「总览」页启动服务器'),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCard() {
    final isCustom = _serverTime?['isCustom'] == true;
    final date = _serverTime?['date'] ?? '-';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.access_time),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('服务器时间', style: Theme.of(context).textTheme.titleSmall),
                Text(date.toString()),
              ],
            ),
          ),
          Chip(
            label: Text(isCustom ? '自定义' : '系统时间'),
            avatar: Icon(isCustom ? Icons.edit_clock : Icons.schedule, size: 16),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _open(Uri.parse(ApiClient.panelUrl('/'))),
            child: const Text('去改时间'),
          ),
        ]),
      ),
    );
  }

  Widget _buildPlayersCard() {
    final players = _players ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.people),
              const SizedBox(width: 8),
              Text('玩家 (${players.length})', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => _open(Uri.parse(ApiClient.panelUrl('/player'))),
                child: const Text('在浏览器管理'),
              ),
            ]),
            const Divider(),
            if (players.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无玩家', style: TextStyle(color: Colors.grey)),
              )
            else
              for (final p in players.take(20))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text('${p['name'] ?? '无名'}'),
                  subtitle: Text('ID: ${p['id']}'),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinksCard() {
    final links = [
      ('/player', '玩家管理', Icons.people),
      ('/mail', '群发邮件', Icons.mail),
      ('/seeds', '抽卡种子', Icons.casino),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('快捷入口', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: links.map((l) {
                final (path, label, icon) = l;
                return ActionChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  onPressed: () => _open(Uri.parse(ApiClient.panelUrl(path))),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
