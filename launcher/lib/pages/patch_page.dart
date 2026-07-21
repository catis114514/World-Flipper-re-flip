import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/patcher.dart';
import '../services/env_check.dart';
import '../services/env_config.dart';
import '../services/paths.dart';
import 'package:path/path.dart' as p;

class PatchPage extends StatefulWidget {
  const PatchPage({super.key});
  @override
  State<PatchPage> createState() => _PatchPageState();
}

class _PatchPageState extends State<PatchPage> {
  final _patcher = Patcher();
  final _apkController = TextEditingController();
  final _keystoreController = TextEditingController();
  final _ksPassController = TextEditingController();
  final _ksAliasController = TextEditingController(text: 'starpoint');
  final _hostController = TextEditingController();

  final _steps = <PatchStep>[];
  bool _busy = false;
  String? _outputApk;
  List<ToolStatus> _tools = [];

  @override
  void initState() {
    super.initState();
    _hostController.text =
        '${EnvConfig.get('CN_LISTEN_HOST', '127.0.0.1')}:${EnvConfig.get('CN_LISTEN_PORT', '8001')}';
    _refreshTools();
  }

  @override
  void dispose() {
    _patcher.dispose();
    _apkController.dispose();
    _keystoreController.dispose();
    _ksPassController.dispose();
    _ksAliasController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _refreshTools() async {
    final tools = await EnvCheck.checkAll();
    if (mounted) setState(() => _tools = tools);
  }

  Future<void> _pickApk() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _apkController.text = result.files.single.path!);
    }
  }

  Future<void> _pickKeystore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jks', 'keystore'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _keystoreController.text = result.files.single.path!);
    }
  }

  Future<void> _runPatch() async {
    final apk = _apkController.text.trim();
    final host = _hostController.text.trim();
    final ks = _keystoreController.text.trim();
    if (apk.isEmpty || host.isEmpty || ks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写 APK、服务器地址、keystore')));
      return;
    }
    setState(() {
      _busy = true;
      _steps.clear();
      _outputApk = null;
    });
    final sub = _patcher.steps.listen((s) {
      setState(() => _steps.add(s));
    });
    final result = await _patcher.patchApk(
      apkPath: apk,
      apiHost: host,
      keystore: ks,
      ksPass: _ksPassController.text,
      ksAlias: _ksAliasController.text,
    );
    await sub.cancel();
    setState(() {
      _busy = false;
      _outputApk = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('客户端补丁', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('全链路：FFDec 反编译 → 改两文件 → 回封 → zipalign → apksigner',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _buildToolsCard(),
          const SizedBox(height: 16),
          _buildFormCard(),
          const SizedBox(height: 16),
          if (_steps.isNotEmpty) _buildStepsCard(),
        ],
      ),
    );
  }

  Widget _buildToolsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('环境检测', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新'),
                onPressed: _refreshTools,
              ),
            ]),
            const Divider(),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: _tools.map((t) {
                final ok = t.ok;
                return Tooltip(
                  message: t.ok ? t.path! : t.help,
                  child: Chip(
                    avatar: Icon(
                      ok ? Icons.check_circle : Icons.error_outline,
                      size: 18,
                      color: ok ? Colors.green : Colors.red,
                    ),
                    label: Text(t.name),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // APK
            TextField(
              controller: _apkController,
              decoration: InputDecoration(
                labelText: '源 APK',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickApk,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Host
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: '重定向地址 (host:port)',
                hintText: '127.0.0.1:8001',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Keystore
            TextField(
              controller: _keystoreController,
              decoration: InputDecoration(
                labelText: '签名 Keystore (.jks)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  onPressed: _pickKeystore,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ksPassController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Keystore 密码',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ksAliasController,
                  decoration: const InputDecoration(
                    labelText: '别名 (alias)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.flash_on),
              label: Text(_busy ? '补丁中...' : '一键打补丁'),
              onPressed: _busy ? null : _runPatch,
            ),
            if (_outputApk != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('完成！输出: ${p.basename(_outputApk!)}')),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('执行步骤', style: TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            for (final s in _steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      s.success ? Icons.check : Icons.close,
                      size: 16,
                      color: s.success ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (s.detail.isNotEmpty)
                            Text(s.detail,
                                style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
