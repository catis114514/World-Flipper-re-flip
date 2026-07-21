/// 存档工具：直接读写 SQLite 存档数据库。
///
/// ⚠️ 重要：数据库路径 .database/wdfp_data.db，且服务器运行时用 WAL 模式打开。
///   - 服务器运行中改存档有风险（数据可能被覆盖/不一致）。
///   - 建议改存档前先停服务器，或改完让玩家重新 /load。
/// better-sqlite3 用 sqlite3 FFI，Dart 端用 sqflite_common_ffi 读同一个文件。
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'paths.dart';

class SaveTools {
  static Future<Database> _open() async {
    sqfliteFfiInit();
    final dbPath = Paths.dbFile;
    final db = await databaseFactoryFfi.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          // 只读场景用 read-only 标记；写操作单独处理
        ));
    return db;
  }

  /// 列出所有玩家（id + name + 当前石头）。
  static Future<List<Map<String, dynamic>>> listPlayers() async {
    final db = await _open();
    try {
      return await db.query('players',
          columns: ['id', 'name', 'free_vmoney', 'vmoney'],
          orderBy: 'id');
    } finally {
      await db.close();
    }
  }

  /// 给指定玩家加免费石。
  static Future<void> addFreeVmoney(int playerId, int amount) async {
    final db = await _open();
    try {
      await db.rawQuery(
        'UPDATE players SET free_vmoney = free_vmoney + ? WHERE id = ?',
        [amount, playerId]);
    } finally {
      await db.close();
    }
  }

  /// 把免费石直接设到指定值。
  static Future<void> setFreeVmoney(int playerId, int value) async {
    final db = await _open();
    try {
      await db.update('players', {'free_vmoney': value},
          where: 'id = ?', whereArgs: [playerId]);
    } finally {
      await db.close();
    }
  }

  /// 解锁辅助位（unison）。
  ///
  /// 根因分析：通关主线后服务端没推进功能解锁标志。
  /// 弹射物语里辅助位解锁通常由 last_main_quest_id 达到某进度 + 某个 mission/option 触发。
  /// 由于 last_main_quest_id 不在 players 表（序列化时动态算），且具体解锁条件
  /// 需逆向 CN 客户端，这里先提供一个"经验性"补齐方案：
  ///   - 补齐主线关键关卡通关记录（players_quest_progress）
  ///   - 触发已完成的 mission（players_active_missions / cleared_regular_mission）
  ///
  /// ⚠️ 这个方法的有效性取决于客户端实际看的字段，可能需要后续调整。
  ///     先实现一个"标记第一章主线全部通关"的版本。
  static Future<String> tryUnlockUnison(int playerId) async {
    final db = await _open();
    final report = StringBuffer();
    try {
      // 1. 查看当前 mission 进度，了解有哪些可解锁项
      final activeMissions = await db.query('players_active_missions',
          where: 'player_id = ?', whereArgs: [playerId]);
      report.writeln('当前 active_missions: ${activeMissions.length} 条');

      // 2. 查看 cleared_regular_mission（已完成的常规任务）
      final cleared = await db.query('players_cleared_regular_missions',
          where: 'player_id = ?', whereArgs: [playerId]);
      report.writeln('已 cleared_regular_missions: ${cleared.length} 条');

      // 3. 查看玩家 options（功能开关可能藏在这）
      final options = await db.query('players_options',
          where: 'player_id = ?', whereArgs: [playerId]);
      report.writeln('玩家 options: ${options.length} 条');
      for (final o in options) {
        report.writeln('  - ${o['key']} = ${o['value']}');
      }

      // 4. 查看 triggered_tutorials（某些教程触发=功能解锁）
      final tutorials = await db.query('players_triggered_tutorials',
          where: 'player_id = ?', whereArgs: [playerId]);
      report.writeln('triggered_tutorials: ${tutorials.length} 条');

      report.writeln('\n⚠️ 辅助位解锁的具体条件需逆向 CN 客户端确认。');
      report.writeln('上面是诊断信息，确定字段后再实现真正的解锁逻辑。');
    } finally {
      await db.close();
    }
    return report.toString();
  }
}
