/// .env 文件读写。
///
/// 保持简单：解析成有序的 key/value 列表，保留注释和空行；写入时整行替换。
/// 这套项目的 .env 全是 KEY=VALUE 形式（部分带引号），不处理 export/shell 语法。
import 'dart:io';
import 'paths.dart';

class EnvLine {
  final String key;
  String value;
  final bool commented; // 是否被注释掉（#KEY=...）
  EnvLine(this.key, this.value, {this.commented = false});
}

class EnvConfig {
  /// 读取 .env，返回 {key: EnvLine}。文件不存在时返回空。
  static Map<String, EnvLine> read() {
    final file = File(Paths.envFile);
    if (!file.existsSync()) return {};
    final lines = file.readAsLinesSync();
    final out = <String, EnvLine>{};
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final commented = line.startsWith('#');
      final content = commented ? line.substring(1).trim() : line;
      final eq = content.indexOf('=');
      if (eq <= 0) continue;
      final key = content.substring(0, eq).trim();
      var value = content.substring(eq + 1).trim();
      // 去掉引号包裹
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
           (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = EnvLine(key, value, commented: commented);
    }
    return out;
  }

  /// 获取单个值，不存在返回默认值。
  static String get(String key, String defaultValue) {
    final map = read();
    return map[key]?.value ?? defaultValue;
  }

  /// 设置一组值并写回 .env。
  /// 策略：逐行扫描，匹配到 KEY= 则整行替换；没匹配到则追加到末尾。
  /// 保留注释和空行。保留未涉及的行原样。
  static void write(Map<String, String> updates) {
    final file = File(Paths.envFile);
    List<String> lines;
    if (file.existsSync()) {
      lines = file.readAsLinesSync();
    } else {
      lines = [];
    }
    final remaining = Map<String, String>.from(updates);
    final result = <String>[];

    for (final raw in lines) {
      final trimmed = raw.trim();
      // 精确匹配 KEY= 或 #KEY=
      String? matchedKey;
      for (final key in remaining.keys) {
        if (trimmed == '$key=' ||
            trimmed.startsWith('$key=') ||
            trimmed == '#$key=' ||
            trimmed.startsWith('#$key=')) {
          matchedKey = key;
          break;
        }
      }
      if (matchedKey != null) {
        result.add('$matchedKey="${remaining[matchedKey]}"');
        remaining.remove(matchedKey);
      } else {
        result.add(raw); // 保留原行
      }
    }

    // 追加新键
    if (remaining.isNotEmpty) {
      if (result.isNotEmpty && result.last.trim().isNotEmpty) {
        result.add('');
      }
      for (final entry in remaining.entries) {
        result.add('${entry.key}="${entry.value}"');
      }
    }

    file.writeAsStringSync(result.join('\n') + '\n');
  }
}
