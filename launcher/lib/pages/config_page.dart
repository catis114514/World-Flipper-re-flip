import 'package:flutter/material.dart';
import '../services/env_config.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});
  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigField {
  final String key;
  final String label;
  final String hint;
  const _ConfigField(this.key, this.label, this.hint);
}

class _ConfigPageState extends State<ConfigPage> {
  static const _fields = [
    _ConfigField('CN_LISTEN_HOST', 'HTTP 绑定地址', '客户端在别的设备时设为 LAN IP'),
    _ConfigField('CN_LISTEN_PORT', 'HTTP 端口', '默认 8001'),
    _ConfigField('CDN_BASE_URL', 'CDN 基础 URL', 'http://<LAN_IP>:<端口>/patch/cn'),
    _ConfigField('CN_RES_VERSION', '资源版本号', '须与客户端一致 (当前 1.4.54)'),
    _ConfigField('DROP_MULTIPLIER', '掉落倍数', '正常为 1，测试可调高'),
    _ConfigField('SESSION_PORT', '联机 TCP 端口', '默认 8003'),
  ];

  final _controllers = <String, TextEditingController>{};
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final cfg = EnvConfig.read();
    for (final f in _fields) {
      _controllers[f.key] = TextEditingController(text: cfg[f.key]?.value ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final updates = <String, String>{};
    for (final f in _fields) {
      updates[f.key] = _controllers[f.key]!.text;
    }
    EnvConfig.write(updates);
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('配置 (.env)',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('保存后需重启服务器生效',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          for (final f in _fields) ...[
            TextFormField(
              controller: _controllers[f.key],
              decoration: InputDecoration(
                labelText: f.label,
                hintText: f.hint,
                border: const OutlineInputBorder(),
                prefixText: '${f.key} = ',
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(children: [
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(_saved ? '已保存 ✓' : '保存'),
              onPressed: _save,
            ),
          ]),
        ],
      ),
    );
  }
}
