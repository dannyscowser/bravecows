import 'dart:io';
import 'dart:math';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/character.dart';
import '../models/study_list.dart';

class DBService {
  DBService._privateConstructor();
  static final DBService instance = DBService._privateConstructor();

  static const _dbName = 'hanzi.sqlite';
  static const _dbVersion = 1;
  static const _assetPath = 'assets/db/hanzi.sqlite';
  static const _cowstownAsset = 'assets/lists/cowstown.txt';
  static const _whosetownAsset = 'assets/lists/whosetown.txt';
  static const _ankiAsset = 'assets/lists/anki_cards_editable.csv';
  static const _ankiFallbackAsset = 'assets/lists/anki_cards.txt';
  static const List<int> _reviewIntervals = [
    10 * 60 * 1000,
    8 * 60 * 60 * 1000,
    24 * 60 * 60 * 1000,
    3 * 24 * 60 * 60 * 1000
  ];
  static const _definitionPenaltyExpr =
      "CASE WHEN LOWER(d2.definitions) LIKE '%variant%' THEN 1 "
      "WHEN LOWER(d2.definitions) LIKE '%surname%' THEN 1 "
      "ELSE 0 END";

  Database? _db;
  int? _defaultListId;
  static const _defaultListSettingKey = 'default_list_id';
  static const _priorMissedListName = 'Prior Missed';
  static const _priorMissedListEmoji = '❌';
  static const _cowstownListName = 'Cowstown';
  static const _cowstownListEmoji = '🐮';
  static const _whosetownListName = 'Whosetown';
  static const _whosetownListEmoji = '👥';
  static const _ankiListName = 'Anki';
  static const _ankiListEmoji = '🃏';
  int? _priorMissedListId;

  Future<void> init() async {
    if (_db != null) return;
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, _dbName);

    final exists = await File(dbPath).exists();
    if (!exists) {
      final data = await rootBundle.load(_assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).create(recursive: true);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onOpen: (db) async => _ensureAppTables(db),
    );
  }

  Future<void> _ensureAppTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reviews (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        traditional TEXT NOT NULL,
        ts INTEGER NOT NULL,
        correct INTEGER NOT NULL,
        list_id INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reviews_trad_ts ON reviews(traditional, ts DESC)');
    await _ensureColumn(db, 'reviews', 'list_id',
        "ALTER TABLE reviews ADD COLUMN list_id INTEGER");

    await db.execute('''
      CREATE TABLE IF NOT EXISTS study (
        traditional TEXT PRIMARY KEY,
        added_ts INTEGER NOT NULL
      )
    ''');

    // Helpful indexes for joins/lookups
    await db.execute('CREATE INDEX IF NOT EXISTS idx_freq_char ON freq(char)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dictionary_trad ON dictionary(traditional)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dictionary_simp ON dictionary(simplified)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dictionary_pinyin ON dictionary(pinyin)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        emoji TEXT,
        is_system INTEGER NOT NULL DEFAULT 0,
        range_start INTEGER,
        range_end INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS list_items (
        traditional TEXT NOT NULL,
        list_id INTEGER NOT NULL,
        meaning TEXT,
        added_ts INTEGER NOT NULL,
        streak INTEGER NOT NULL DEFAULT 0,
        next_due INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        PRIMARY KEY(traditional, list_id, meaning)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_list_items_list ON list_items(list_id, traditional)');

    // Build an FTS table to speed up search if it does not yet exist.
    final hasFts = await _tableExists(db, 'dictionary_fts');
    if (!hasFts) {
      await db.execute('''
        CREATE VIRTUAL TABLE dictionary_fts USING fts5(
          traditional,
          simplified,
          pinyin,
          content="dictionary",
          content_rowid="id"
        )
      ''');
      await db.rawInsert(
          'INSERT INTO dictionary_fts(dictionary_fts) VALUES(\'rebuild\')');
    } else {
      // Ensure indexes exist even if tables predate this schema.
      await db.rawInsert(
          'INSERT INTO dictionary_fts(dictionary_fts) VALUES(\'rebuild\')');
    }

    // Ensure a default list exists and migrate legacy study entries.
    final defaultId = await _ensureDefaultList(db);
    final hasLegacyStudy =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM study'))!;
    final hasListItems = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM list_items'))!;
    if (hasLegacyStudy > 0 && hasListItems == 0) {
      final rows = await db.query('study', columns: ['traditional']);
      final batch = db.batch();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final r in rows) {
        batch.insert(
          'list_items',
          {
            'traditional': r['traditional'],
            'list_id': defaultId,
            'meaning': null,
            'added_ts': now
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    }
    await _ensureColumn(db, 'list_items', 'streak',
        "ALTER TABLE list_items ADD COLUMN streak INTEGER NOT NULL DEFAULT 0");
    await _ensureColumn(db, 'list_items', 'next_due',
        "ALTER TABLE list_items ADD COLUMN next_due INTEGER NOT NULL DEFAULT 0");
    await db.execute(
        'UPDATE list_items SET next_due = strftime(\'%s\',\'now\')*1000 WHERE next_due = 0');
    await _ensureColumn(db, 'lists', 'is_system',
        "ALTER TABLE lists ADD COLUMN is_system INTEGER NOT NULL DEFAULT 0");
    await _ensureColumn(db, 'lists', 'range_start',
        "ALTER TABLE lists ADD COLUMN range_start INTEGER");
    await _ensureColumn(db, 'lists', 'range_end',
        "ALTER TABLE lists ADD COLUMN range_end INTEGER");
    await _ensureSystemLists(db);
    await _ensureCustomLists(db);
    _defaultListId = defaultId;
  }

  Future<void> _ensureColumn(
      Database db, String table, String column, String ddl) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == column);
    if (!exists) {
      try {
        await db.execute(ddl);
      } catch (_) {}
    }
  }

  Future<void> _ensureSystemLists(Database db) async {
    final bands = [
      {'name': 'Top 1-1000', 'start': 0, 'end': 1000, 'emoji': '🔥'},
      {'name': 'Top 1001-2000', 'start': 1000, 'end': 2000, 'emoji': '💥'},
      {'name': 'Top 2001-3000', 'start': 2000, 'end': 3000, 'emoji': '⚡️'},
      {'name': 'Top 3001-4000', 'start': 3000, 'end': 4000, 'emoji': '🌟'},
      {'name': 'Top 4001-5000', 'start': 4000, 'end': 5000, 'emoji': '⭐️'},
    ];
    for (final band in bands) {
      final existing = await db.query('lists',
          where: 'is_system = 1 AND range_start = ? AND range_end = ?',
          whereArgs: [band['start'], band['end']],
          limit: 1);
      if (existing.isEmpty) {
        await db.insert('lists', {
          'name': band['name'],
          'emoji': band['emoji'],
          'is_system': 1,
          'range_start': band['start'],
          'range_end': band['end']
        });
      }
    }
    // Ensure Prior Missed list exists.
    final prior = await db.query('lists',
        where: 'name = ?', whereArgs: [_priorMissedListName], limit: 1);
    if (prior.isEmpty) {
      await db.insert('lists', {
        'name': _priorMissedListName,
        'emoji': _priorMissedListEmoji,
        'is_system': 1,
        'range_start': null,
        'range_end': null,
      });
    }
  }

  Future<void> _ensureCustomLists(Database db) async {
    await _ensureAssetBackedList(
      db,
      name: _cowstownListName,
      emoji: _cowstownListEmoji,
      assetPath: _cowstownAsset,
    );
    await _ensureAssetBackedList(
      db,
      name: _whosetownListName,
      emoji: _whosetownListEmoji,
      assetPath: _whosetownAsset,
    );
    await _ensureAssetBackedList(
      db,
      name: _ankiListName,
      emoji: _ankiListEmoji,
      assetPath: _ankiAsset,
    );
  }

  Future<void> ensureAssetListPopulated(int listId) async {
    final db = _db!;
    final rows =
        await db.query('lists', where: 'id = ?', whereArgs: [listId], limit: 1);
    if (rows.isEmpty) return;
    final row = rows.first;
    final name = row['name'] as String? ?? '';
    if (name == _cowstownListName) {
      await _ensureAssetBackedList(
        db,
        name: _cowstownListName,
        emoji: _cowstownListEmoji,
        assetPath: _cowstownAsset,
      );
    } else if (name == _whosetownListName) {
      await _ensureAssetBackedList(
        db,
        name: _whosetownListName,
        emoji: _whosetownListEmoji,
        assetPath: _whosetownAsset,
      );
    } else if (name == _ankiListName) {
      await _ensureAssetBackedList(
        db,
        name: _ankiListName,
        emoji: _ankiListEmoji,
        assetPath: _ankiAsset,
      );
    }
  }

  Future<void> _ensureAssetBackedList(Database db,
      {required String name,
      required String emoji,
      required String assetPath}) async {
    final listId = await _ensureNamedList(db, name, emoji: emoji);
    if (assetPath.endsWith('anki_cards_editable.csv') ||
        assetPath.endsWith('anki_cards.txt')) {
      await db.delete('list_items', where: 'list_id = ?', whereArgs: [listId]);
      await db.delete('anki_cards');
    }
    // Special-case Anki cards, preferring the editable CSV source of truth.
    if (assetPath.endsWith('anki_cards_editable.csv') ||
        assetPath.endsWith('anki_cards.txt')) {
      try {
        // Ensure anki_cards table exists
        await db.execute('''
          CREATE TABLE IF NOT EXISTS anki_cards (
            phrase TEXT PRIMARY KEY,
            english_def TEXT,
            pinyin TEXT,
            english_example TEXT,
            chinese_example TEXT,
            audio TEXT
          )
        ''');

        final batch = db.batch();
        final now = DateTime.now().millisecondsSinceEpoch;
        if (assetPath.endsWith('anki_cards_editable.csv')) {
          final raw = await rootBundle.loadString(assetPath);
          final reader = CsvToListConverter(eol: '\n').convert(raw);
          for (final row in reader.skip(1)) {
            if (row.isEmpty) continue;
            final phrase = row.isNotEmpty ? row[0].toString().trim() : '';
            final englishDef = row.length > 1 ? row[1].toString().trim() : '';
            final pinyin = row.length > 2 ? row[2].toString().trim() : '';
            final engEx = row.length > 3 ? row[3].toString().trim() : '';
            final chiEx = row.length > 4 ? row[4].toString().trim() : '';
            if (phrase.isEmpty) continue;
            batch.insert(
              'anki_cards',
              {
                'phrase': phrase,
                'english_def': englishDef,
                'pinyin': pinyin,
                'english_example': engEx,
                'chinese_example': chiEx,
                'audio': null,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            batch.insert(
              'list_items',
              {
                'traditional': phrase,
                'list_id': listId,
                'meaning': englishDef.isEmpty ? null : englishDef,
                'added_ts': now,
                'streak': 0,
                'next_due': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        } else {
          final raw = await rootBundle.loadString(assetPath);
          final lines = raw.split(RegExp(r'\r?\n'));
          for (final rawLine in lines) {
            final line = rawLine.trim();
            if (line.isEmpty) continue;
            // Split into up to 6 fields
            final parts = line.split('|');
            if (parts.isEmpty) continue;
            final phrase = parts.isNotEmpty ? parts[0].trim() : '';
            final englishDef = parts.length > 1 ? parts[1].trim() : '';
            final pinyin = parts.length > 2 ? parts[2].trim() : '';
            final engEx = parts.length > 3 ? parts[3].trim() : '';
            final chiEx = parts.length > 4 ? parts[4].trim() : '';
            final audio = parts.length > 5 ? parts[5].trim() : null;
            if (phrase.isEmpty) continue;
            batch.insert(
              'anki_cards',
              {
                'phrase': phrase,
                'english_def': englishDef,
                'pinyin': pinyin,
                'english_example': engEx,
                'chinese_example': chiEx,
                'audio': audio,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            batch.insert(
              'list_items',
              {
                'traditional': phrase,
                'list_id': listId,
                'meaning': englishDef.isEmpty ? null : englishDef,
                'added_ts': now,
                'streak': 0,
                'next_due': now,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        await batch.commit(noResult: true);
      } catch (_) {
        if (assetPath.endsWith('anki_cards_editable.csv')) {
          await _ensureAssetBackedList(
            db,
            name: name,
            emoji: emoji,
            assetPath: _ankiFallbackAsset,
          );
        }
        return;
      }
      return;
    }

    // Fallback: old single-character list parsing
    List<String> chars = [];
    try {
      final raw = await rootBundle.loadString(assetPath);
      final seen = <String>{};
      for (final line in raw.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.length != 1) continue;
        if (seen.add(trimmed)) {
          chars.add(trimmed);
        }
      }
    } catch (_) {
      return;
    }
    if (chars.isEmpty) return;
    // Filter out characters that do not exist in the dictionary to avoid empty joins.
    final filtered = <String>[];
    const chunkSize = 200;
    for (var i = 0; i < chars.length; i += chunkSize) {
      final chunk = chars.sublist(i, min(i + chunkSize, chars.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT traditional, simplified
        FROM dictionary
        WHERE traditional IN ($placeholders)
           OR simplified IN ($placeholders)
        ''',
        [...chunk, ...chunk],
      );
      final have = <String>{};
      for (final row in rows) {
        final trad = row['traditional'] as String?;
        final simp = row['simplified'] as String?;
        if (trad != null) have.add(trad);
        if (simp != null) have.add(simp);
      }
      for (final ch in chunk) {
        if (have.contains(ch)) {
          filtered.add(ch);
        }
      }
    }
    chars = filtered;
    if (chars.isEmpty) return;
    final existingRows = await db.query('list_items',
        columns: ['traditional'], where: 'list_id = ?', whereArgs: [listId]);
    final existing =
        existingRows.map((r) => r['traditional'] as String).toSet();
    final missing = chars.where((c) => !existing.contains(c)).toList();
    if (missing.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final ch in missing) {
      batch.insert(
        'list_items',
        {
          'traditional': ch,
          'list_id': listId,
          'meaning': null,
          'added_ts': now,
          'streak': 0,
          'next_due': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> _ensureNamedList(Database db, String name,
      {String? emoji, bool isSystem = true}) async {
    final existing =
        await db.query('lists', where: 'name = ?', whereArgs: [name], limit: 1);
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return db.insert('lists', {
      'name': name,
      'emoji': emoji,
      'is_system': isSystem ? 1 : 0,
      'range_start': null,
      'range_end': null,
    });
  }

  Future<int> _ensureDefaultList(Database db) async {
    final existing = await db.query('lists', limit: 1);
    if (existing.isNotEmpty) {
      final first = existing.first;
      final id = first['id'] as int;
      final emoji = first['emoji'] as String?;
      final name = first['name'] as String?;
      if (emoji == '📚' ||
          emoji == null ||
          (name != null && name == 'General' && emoji != '🫡')) {
        await db.update('lists', {'emoji': '🫡'},
            where: 'id = ?', whereArgs: [id]);
      }
      return id;
    }
    final id = await db.insert('lists', {'name': 'General', 'emoji': '🫡'});
    return id;
  }

  Future<int> defaultListId() async {
    if (_defaultListId != null) return _defaultListId!;
    final db = _db!;
    final saved = await db.query('settings',
        where: 'key = ?', whereArgs: [_defaultListSettingKey], limit: 1);
    if (saved.isNotEmpty) {
      final raw = saved.first['value'] as String?;
      final parsed = int.tryParse(raw ?? '');
      if (parsed != null) {
        _defaultListId = parsed;
        return _defaultListId!;
      }
    }
    _defaultListId = await _ensureDefaultList(db);
    return _defaultListId!;
  }

  Future<void> setDefaultListId(int listId) async {
    final db = _db!;
    _defaultListId = listId;
    await db.insert(
      'settings',
      {'key': _defaultListSettingKey, 'value': '$listId'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setSetting(String key, String value) async {
    final db = _db!;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = _db!;
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<int?> getIntSetting(String key) async {
    final raw = await getSetting(key);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<int> _ensurePriorMissedListId() async {
    if (_priorMissedListId != null) return _priorMissedListId!;
    final db = _db!;
    final existing = await db.query('lists',
        where: 'name = ?', whereArgs: [_priorMissedListName], limit: 1);
    if (existing.isNotEmpty) {
      _priorMissedListId = existing.first['id'] as int;
      return _priorMissedListId!;
    }
    final id = await db.insert('lists', {
      'name': _priorMissedListName,
      'emoji': _priorMissedListEmoji,
      'is_system': 1,
    });
    _priorMissedListId = id;
    return id;
  }

  Future<List<StudyList>> getLists() async {
    final db = _db!;
    final rows = await db.query('lists', orderBy: 'id ASC');
    return rows
        .map((r) => StudyList(
              id: r['id'] as int,
              name: r['name'] as String,
              emoji: r['emoji'] as String?,
              isSystem: (r['is_system'] as int? ?? 0) == 1,
              rangeStart: r['range_start'] as int?,
              rangeEnd: r['range_end'] as int?,
            ))
        .toList();
  }

  Future<int> createList(String name, {String? emoji}) async {
    final db = _db!;
    return db.insert('lists', {'name': name, 'emoji': emoji});
  }

  Future<void> addToList(String traditional, int listId,
      {String? meaning}) async {
    final db = _db!;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'list_items',
      {
        'traditional': traditional,
        'list_id': listId,
        'meaning': meaning,
        'added_ts': now,
        'streak': 0,
        'next_due': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> populateSystemList(StudyList list) async {
    if (!list.isSystem || list.rangeStart == null || list.rangeEnd == null) {
      return;
    }
    final db = _db!;
    final size = list.rangeEnd! - list.rangeStart!;
    if (size <= 0) return;
    final existing = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM list_items WHERE list_id = ?', [list.id])) ??
        0;
    if (existing >= size) return;
    final rows = await db.rawQuery('''
      SELECT d.traditional,
             d.simplified,
             d.pinyin,
             d.definitions,
             f.frequency
      FROM dictionary d
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE length(d.traditional) = 1
      GROUP BY d.traditional
      ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
      LIMIT ? OFFSET ?
    ''', [size, list.rangeStart]);
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in rows) {
      batch.insert(
        'list_items',
        {
          'traditional': r['traditional'],
          'list_id': list.id,
          'meaning': null,
          'added_ts': now,
          'streak': 0,
          'next_due': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, int>> getListStats(int listId) async {
    final db = _db!;
    final total = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(DISTINCT traditional) FROM list_items WHERE list_id = ?',
        [listId]))!;
    final known = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(DISTINCT traditional) FROM list_items WHERE list_id = ? AND streak >= 4',
        [listId]))!;
    return {
      'total': total,
      'known': known,
      'unknown': total - known,
    };
  }

  Future<List<Character>> getListItems(int listId,
      {int limit = 200, int offset = 0}) async {
    final db = _db!;
    final rows = await db.rawQuery('''
      SELECT COALESCE(d.traditional, s.traditional) AS traditional,
             d.simplified,
             COALESCE(a.pinyin, d.pinyin) AS pinyin,
             d.definitions,
             f.frequency,
             MAX(s.streak) AS streak
      FROM list_items s
      LEFT JOIN dictionary d ON d.id = (
        SELECT d2.id
        FROM dictionary d2
        LEFT JOIN freq f2 ON (d2.traditional = f2.char OR d2.simplified = f2.char)
        WHERE d2.traditional = s.traditional
        ORDER BY $_definitionPenaltyExpr ASC,
                 COALESCE(f2.frequency, 0) DESC,
                 d2.id ASC
        LIMIT 1
      )
      LEFT JOIN anki_cards a ON a.phrase = s.traditional
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE s.list_id = ?
      GROUP BY COALESCE(d.traditional, s.traditional)
      ORDER BY COALESCE(f.frequency, 0) DESC, COALESCE(d.traditional, s.traditional)
      LIMIT ? OFFSET ?
    ''', [listId, limit, offset]);
    return rows
        .map((r) => _mapToCharacter(r,
            isKnown: (r['streak'] is int && (r['streak'] as int) >= 4)))
        .toList();
  }

  Future<void> removeFromList(String traditional, int listId,
      {String? meaning}) async {
    final db = _db!;
    await db.delete(
      'list_items',
      where:
          'traditional = ? AND list_id = ? AND (meaning IS ? OR meaning = ?)',
      whereArgs: [traditional, listId, meaning, meaning],
    );
  }

  Future<List<Character>> getCollection(
      {int limit = 5000, int offset = 0}) async {
    final db = _db!;
    final rows = await db.rawQuery('''
      SELECT d.traditional,
             MIN(d.simplified) AS simplified,
             MIN(d.pinyin) AS pinyin,
             MIN(d.definitions) AS definitions,
             MAX(f.frequency) AS frequency
      FROM freq f
      JOIN dictionary d ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE length(f.char) = 1
      GROUP BY d.traditional
      ORDER BY COALESCE(MAX(f.frequency), 0) DESC, d.traditional
      LIMIT ? OFFSET ?
    ''', [limit, offset]);
    return rows.map(_mapToCharacter).toList();
  }

  Future<Set<String>> getAllListItems() async {
    final db = _db!;
    final rows =
        await db.query('list_items', columns: ['DISTINCT traditional']);
    return rows.map((r) => r['traditional'] as String).toSet();
  }

  Future<List<Character>> search(String query) async {
    final db = _db!;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    // Normalize pinyin: drop spaces, tones, and separators for prefix matching.
    final normalized = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[1-5]'), '')
        .replaceAll(RegExp(r"['`-]"), '');
    final normalizedPrefix = '$normalized%';
    // Build prefix-match tokens for FTS so typing "guo" matches guo*, pinyin, or hanzi.
    final tokens = trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    final match = tokens.map((t) => '$t*').join(' ');
    try {
      final rows = await db.rawQuery('''
        SELECT d.traditional,
               MIN(d.simplified) AS simplified,
               MIN(d.pinyin) AS pinyin,
               MIN(d.definitions) AS definitions,
               MAX(f.frequency) AS frequency
        FROM dictionary_fts fts
        JOIN dictionary d ON d.id = fts.rowid
        LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
        WHERE dictionary_fts MATCH ?
        GROUP BY d.traditional
        ORDER BY COALESCE(MAX(f.frequency), 0) DESC, d.traditional
        LIMIT 50
      ''', [match]);
      if (rows.isNotEmpty) {
        return rows.map(_mapToCharacter).toList();
      }
    } catch (_) {
      // ignore and fallback below
    }
    // Fallback to indexed prefix search (and normalized pinyin) if FTS is empty or unavailable.
    final prefix = '$trimmed%';
    final lowerPrefix = prefix.toLowerCase();
    final rows = await db.rawQuery('''
      SELECT d.traditional,
             MIN(d.simplified) AS simplified,
             MIN(d.pinyin) AS pinyin,
             MIN(d.definitions) AS definitions,
             MAX(f.frequency) AS frequency
      FROM dictionary d
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE d.traditional LIKE ?
         OR d.simplified LIKE ?
         OR LOWER(d.pinyin) LIKE ?
         OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(LOWER(d.pinyin), ' ', ''), '-', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', '') LIKE ?
      GROUP BY d.traditional
      ORDER BY COALESCE(MAX(f.frequency), 0) DESC, d.traditional
      LIMIT 50
    ''', [prefix, prefix, lowerPrefix, normalizedPrefix]);
    return rows.map(_mapToCharacter).toList();
  }

  Future<Character?> getCharacter(String traditional) async {
    final db = _db!;
    final rows = await db.rawQuery('''
      SELECT d.traditional, d.simplified, d.pinyin, d.definitions, f.frequency,
             COALESCE(s.streak, 0) AS streak
      FROM dictionary d
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      LEFT JOIN (
        SELECT traditional, MAX(streak) AS streak
        FROM list_items
        GROUP BY traditional
      ) s ON s.traditional = d.traditional
      WHERE d.traditional = ?
      ORDER BY $_definitionPenaltyExpr ASC,
               COALESCE(f.frequency, 0) DESC,
               d.id ASC
      LIMIT 1
    ''', [traditional]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final isKnown = row['streak'] is int && (row['streak'] as int) >= 4;
    return _mapToCharacter(row, isKnown: isKnown);
  }

  Future<Set<String>> getStudySet({int? listId}) async {
    final db = _db!;
    final targetList = listId ?? await defaultListId();
    final rows = await db.query('list_items',
        columns: ['traditional'],
        where: 'list_id = ?',
        whereArgs: [targetList]);
    return rows.map((r) => r['traditional'] as String).toSet();
  }

  Future<void> addToStudy(String traditional, {int? listId}) async {
    final targetList = listId ?? await defaultListId();
    await addToList(traditional, targetList);
  }

  Future<void> removeFromStudy(String traditional, {int? listId}) async {
    final targetList = listId ?? await defaultListId();
    await removeFromList(traditional, targetList);
  }

  Future<List<Character>> getDueCharacters(
      {int limitUnknown = 25, int limitKnown = 1, int? listId}) async {
    final db = _db!;
    final targetList = listId ?? await defaultListId();
    final now = DateTime.now().millisecondsSinceEpoch;

    List<Map<String, Object?>> rowsUnknown = await db.rawQuery('''
      SELECT s.traditional, d.simplified, COALESCE(a.pinyin, d.pinyin) AS pinyin, d.definitions, f.frequency
      FROM list_items s
      JOIN dictionary d ON d.id = (
        SELECT d2.id
        FROM dictionary d2
        LEFT JOIN freq f2 ON (d2.traditional = f2.char OR d2.simplified = f2.char)
        WHERE d2.traditional = s.traditional
        ORDER BY $_definitionPenaltyExpr ASC,
                 COALESCE(f2.frequency, 0) DESC,
                 d2.id ASC
        LIMIT 1
      )
      LEFT JOIN anki_cards a ON a.phrase = s.traditional
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE s.list_id = ?
        AND COALESCE(s.streak, 0) < 4
        AND COALESCE(s.next_due, 0) <= ?
      GROUP BY s.traditional
      ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
      LIMIT ?
    ''', [targetList, now, limitUnknown]);

    if (rowsUnknown.length < limitUnknown) {
      final missing = limitUnknown - rowsUnknown.length;
      final notIn = rowsUnknown
          .map((r) => r['traditional'] as String)
          .toList(growable: false);
      final fillers = await db.rawQuery('''
        SELECT s.traditional, d.simplified, COALESCE(a.pinyin, d.pinyin) AS pinyin, d.definitions, f.frequency
        FROM list_items s
        JOIN dictionary d ON d.traditional = s.traditional
        LEFT JOIN anki_cards a ON a.phrase = s.traditional
        LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
        WHERE s.list_id = ?
          AND COALESCE(s.streak, 0) < 4
          ${notIn.isEmpty ? '' : 'AND s.traditional NOT IN (${List.filled(notIn.length, '?').join(',')})'}
        GROUP BY s.traditional
        ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
        LIMIT ?
      ''', [targetList, ...notIn, missing]);
      rowsUnknown = [...rowsUnknown, ...fillers];
    }

    List<Map<String, Object?>> rowsKnown = await db.rawQuery('''
      SELECT s.traditional, d.simplified, COALESCE(a.pinyin, d.pinyin) AS pinyin, d.definitions, f.frequency
      FROM list_items s
      JOIN dictionary d ON d.id = (
        SELECT d2.id
        FROM dictionary d2
        LEFT JOIN freq f2 ON (d2.traditional = f2.char OR d2.simplified = f2.char)
        WHERE d2.traditional = s.traditional
        ORDER BY $_definitionPenaltyExpr ASC,
                 COALESCE(f2.frequency, 0) DESC,
                 d2.id ASC
        LIMIT 1
      )
      LEFT JOIN anki_cards a ON a.phrase = s.traditional
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE s.list_id = ?
        AND COALESCE(s.streak, 0) >= 4
        AND COALESCE(s.next_due, 0) <= ?
      GROUP BY s.traditional
      ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
      LIMIT ?
    ''', [targetList, now, limitKnown]);

    if (rowsKnown.length < limitKnown) {
      final missing = limitKnown - rowsKnown.length;
      final notIn = [
        ...rowsUnknown.map((r) => r['traditional'] as String),
        ...rowsKnown.map((r) => r['traditional'] as String),
      ];
      final fillers = await db.rawQuery('''
        SELECT s.traditional, d.simplified, COALESCE(a.pinyin, d.pinyin) AS pinyin, d.definitions, f.frequency
        FROM list_items s
        JOIN dictionary d ON d.traditional = s.traditional
        LEFT JOIN anki_cards a ON a.phrase = s.traditional
        LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
        WHERE s.list_id = ?
          AND COALESCE(s.streak, 0) >= 4
          ${notIn.isEmpty ? '' : 'AND s.traditional NOT IN (${List.filled(notIn.length, '?').join(',')})'}
        GROUP BY s.traditional
        ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
        LIMIT ?
      ''', [targetList, ...notIn, missing]);
      rowsKnown = [...rowsKnown, ...fillers];
    }

    return [
      ...rowsUnknown.map((r) => _mapToCharacter(r, isKnown: false)),
      ...rowsKnown.map((r) => _mapToCharacter(r, isKnown: true)),
    ];
  }

  Future<List<Character>> getLearnCandidates({int limit = 300}) async {
    final db = _db!;
    final rows = await db.rawQuery('''
      SELECT d.traditional, d.simplified, d.pinyin, d.definitions, f.frequency
      FROM freq f
      JOIN dictionary d ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE length(f.char) = 1
        AND d.traditional NOT IN (SELECT DISTINCT traditional FROM list_items)
      ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
      LIMIT ?
    ''', [limit]);
    return rows.map(_mapToCharacter).toList();
  }

  Future<List<Character>> getLearnBatch(
      {int total = 25, int maxKnown = 5, int? seed, int? excludeListId}) async {
    final candidates =
        await _queryLearnCandidates(excludeListId: excludeListId);
    return _sampleSplitCandidates(
      candidates,
      desiredTotal: total,
      desiredKnown: maxKnown,
      seed: seed,
    );
  }

  Future<List<Character>> getPracticeCharacters(
      {int limitUnknown = 25,
      int limitKnown = 0,
      int? listId,
      int? seed}) async {
    final targetList = listId ?? await defaultListId();
    final candidates = await _queryListCandidates(targetList);
    return _sampleSplitCandidates(
      candidates,
      desiredTotal: limitUnknown + limitKnown,
      desiredKnown: limitKnown,
      seed: seed,
    );
  }

  Future<List<Character>> getAllCharactersForList(int listId,
      {int? limit,
      int offset = 0,
      bool unknownFirst = true,
      bool includeKnown = true}) async {
    var candidates = await _queryListCandidates(listId);
    if (!includeKnown) {
      candidates = candidates.where((candidate) => !candidate.isKnown).toList();
    }
    final sampled = _sampleCandidates(candidates, limit ?? candidates.length,
        seed: DateTime.now().microsecondsSinceEpoch);
    if (offset <= 0) return sampled;
    if (offset >= sampled.length) return [];
    final end =
        limit == null ? sampled.length : min(sampled.length, offset + limit);
    return sampled.sublist(offset, end);
  }

  Future<List<Character>> getWrongCharactersForList(int? listId,
      {int? limit}) async {
    final db = _db!;
    final targetList = listId ?? await defaultListId();
    final params = <Object?>[targetList];
    final buffer = StringBuffer('''
      SELECT d.traditional,
             MIN(d.simplified) AS simplified,
             MIN(d.pinyin) AS pinyin,
             MIN(d.definitions) AS definitions,
             MAX(f.frequency) AS frequency,
             MAX(r.ts) AS last_ts
      FROM reviews r
      JOIN dictionary d ON d.traditional = r.traditional
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE r.correct = 0
        AND (r.list_id = ? OR r.list_id IS NULL)
      GROUP BY r.traditional
      ORDER BY last_ts DESC
    ''');
    if (limit != null) {
      buffer.write(' LIMIT ?');
      params.add(limit);
    }
    final rows = await db.rawQuery(buffer.toString(), params);
    return rows.map(_mapToCharacter).toList();
  }

  Future<List<Character>> getLearnBand(
      {int start = 0, int size = 100, int? excludeListId}) async {
    final db = _db!;
    final params = <Object?>[];
    final buffer = StringBuffer('''
      SELECT d.traditional, d.simplified, d.pinyin, d.definitions, f.frequency
      FROM freq f
      JOIN dictionary d ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE length(f.char) = 1
        AND d.traditional >= '一' AND d.traditional <= '龯'
    ''');
    if (excludeListId != null) {
      buffer.write(
          ' AND d.traditional NOT IN (SELECT traditional FROM list_items WHERE list_id = ?)');
      params.add(excludeListId);
    }
    buffer.write('''
      GROUP BY d.traditional
      ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional
      LIMIT ? OFFSET ?
    ''');
    params
      ..add(size)
      ..add(start);
    final rows = await db.rawQuery(buffer.toString(), params);
    return rows.map(_mapToCharacter).toList();
  }

  Future<List<_StudyCandidate>> _queryLearnCandidates(
      {int? excludeListId}) async {
    final db = _db!;
    final recentCutoff =
        DateTime.now().millisecondsSinceEpoch - 14 * 24 * 60 * 60 * 1000;
    final params = <Object?>[recentCutoff];
    final excludeClause = excludeListId != null
        ? 'AND d.traditional NOT IN (SELECT traditional FROM list_items WHERE list_id = ?)'
        : '';
    if (excludeListId != null) {
      params.add(excludeListId);
    }
    final rows = await db.rawQuery('''
      WITH streaks AS (
        SELECT traditional, MAX(streak) AS streak
        FROM list_items
        GROUP BY traditional
      ),
      reviews_agg AS (
        SELECT traditional,
               MAX(ts) AS last_seen_ts,
               MAX(CASE WHEN correct = 0 THEN ts END) AS last_wrong_ts,
               SUM(CASE WHEN correct = 0 AND ts >= ? THEN 1 ELSE 0 END) AS recent_wrong_count
        FROM reviews
        GROUP BY traditional
      )
      SELECT d.traditional,
             d.simplified,
             d.pinyin,
             d.definitions,
             MAX(f.frequency) AS frequency,
             COALESCE(s.streak, 0) AS streak,
             r.last_seen_ts,
             r.last_wrong_ts,
             COALESCE(r.recent_wrong_count, 0) AS recent_wrong_count
      FROM dictionary d
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      LEFT JOIN streaks s ON s.traditional = d.traditional
      LEFT JOIN reviews_agg r ON r.traditional = d.traditional
      WHERE length(d.traditional) BETWEEN 1 AND 2
      $excludeClause
      GROUP BY d.traditional
      ORDER BY COALESCE(MAX(f.frequency), 0) DESC, d.traditional
    ''', params);
    return _rowsToCandidates(rows);
  }

  Future<List<_StudyCandidate>> _queryListCandidates(int listId) async {
    final db = _db!;
    final recentCutoff =
        DateTime.now().millisecondsSinceEpoch - 14 * 24 * 60 * 60 * 1000;
    final rows = await db.rawQuery('''
      WITH reviews_agg AS (
        SELECT traditional,
               MAX(ts) AS last_seen_ts,
               MAX(CASE WHEN correct = 0 THEN ts END) AS last_wrong_ts,
               SUM(CASE WHEN correct = 0 AND ts >= ? THEN 1 ELSE 0 END) AS recent_wrong_count
        FROM reviews
        GROUP BY traditional
      )
      SELECT COALESCE(d.traditional, s.traditional) AS traditional,
              COALESCE(d.simplified, s.traditional) AS simplified,
              COALESCE(a.pinyin, d.pinyin, '') AS pinyin,
              COALESCE(d.definitions, s.meaning, '') AS definitions,
             MAX(f.frequency) AS frequency,
             MAX(s.streak) AS streak,
             r.last_seen_ts,
             r.last_wrong_ts,
             COALESCE(r.recent_wrong_count, 0) AS recent_wrong_count
      FROM list_items s
            LEFT JOIN dictionary d ON d.traditional = s.traditional
            LEFT JOIN anki_cards a ON a.phrase = s.traditional
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      LEFT JOIN reviews_agg r ON r.traditional = s.traditional
      WHERE s.list_id = ?
      GROUP BY COALESCE(d.traditional, s.traditional)
      ORDER BY COALESCE(MAX(f.frequency), 0) DESC, COALESCE(d.traditional, s.traditional)
    ''', [recentCutoff, listId]);
    return _rowsToCandidates(rows);
  }

  List<_StudyCandidate> _rowsToCandidates(List<Map<String, Object?>> rows) {
    final candidates = <_StudyCandidate>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      candidates.add(
        _StudyCandidate(
          character: _mapToCharacter(row,
              isKnown: (row['streak'] is int && (row['streak'] as int) >= 4)),
          rank: i + 1,
          lastSeenTs: row['last_seen_ts'] as int?,
          lastWrongTs: row['last_wrong_ts'] as int?,
          recentWrongCount: row['recent_wrong_count'] as int? ?? 0,
          isKnown: (row['streak'] is int && (row['streak'] as int) >= 4),
        ),
      );
    }
    return candidates;
  }

  List<Character> _sampleCandidates(List<_StudyCandidate> candidates, int count,
      {int? seed}) {
    if (count <= 0 || candidates.isEmpty) return [];
    final rng = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    final now = DateTime.now();
    final scored = candidates.map((candidate) {
      final weight = _candidateWeight(candidate, now);
      final safeWeight = weight.isFinite && weight > 0 ? weight : 0.000001;
      final key = -log(max(rng.nextDouble(), 0.0000001)) / safeWeight;
      return _ScoredCandidate(candidate, key);
    }).toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final chosen = scored
        .take(min(count, scored.length))
        .map((item) => item.candidate.character)
        .toList();
    chosen.shuffle(rng);
    return chosen;
  }

  List<Character> _sampleSplitCandidates(List<_StudyCandidate> candidates,
      {required int desiredTotal, required int desiredKnown, int? seed}) {
    if (desiredTotal <= 0 || candidates.isEmpty) return [];
    final rng = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    final knownCandidates =
        candidates.where((candidate) => candidate.isKnown).toList();
    final unknownCandidates =
        candidates.where((candidate) => !candidate.isKnown).toList();
    final selected = <Character>[];
    final seen = <String>{};

    final desiredUnknown = max(desiredTotal - desiredKnown, 0);
    final unknownSelection = _sampleCandidates(
      unknownCandidates,
      min(desiredUnknown, unknownCandidates.length),
      seed: rng.nextInt(1 << 31),
    );
    for (final item in unknownSelection) {
      if (seen.add(item.traditional)) {
        selected.add(item);
      }
    }

    final knownSelection = _sampleCandidates(
      knownCandidates,
      min(desiredKnown, knownCandidates.length),
      seed: rng.nextInt(1 << 31),
    );
    for (final item in knownSelection) {
      if (selected.length >= desiredTotal) break;
      if (seen.add(item.traditional)) {
        selected.add(item);
      }
    }

    if (selected.length < desiredTotal) {
      final leftovers = candidates
          .where((candidate) => seen.add(candidate.character.traditional))
          .map((candidate) => candidate.character)
          .toList();
      leftovers.shuffle(rng);
      selected.addAll(leftovers.take(desiredTotal - selected.length));
    }

    selected.shuffle(rng);
    return selected.take(desiredTotal).toList();
  }

  double _candidateWeight(_StudyCandidate candidate, DateTime now) {
    final rankWeight = 1 / pow(max(candidate.rank, 1).toDouble(), 0.7);
    final recentPenalty = _recentExposureMultiplier(candidate.lastSeenTs, now);
    final wrongBoost = _recentWrongBoost(
        candidate.recentWrongCount, candidate.lastWrongTs, now);
    return max(0.000001, rankWeight * recentPenalty * wrongBoost);
  }

  double _recentExposureMultiplier(int? lastSeenTs, DateTime now) {
    if (lastSeenTs == null) return 1;
    final ageHours = now
            .difference(DateTime.fromMillisecondsSinceEpoch(lastSeenTs))
            .inMinutes /
        60.0;
    final decay = 1 - (0.65 * exp(-ageHours / 24.0));
    return decay.clamp(0.35, 1.0).toDouble();
  }

  double _recentWrongBoost(
      int recentWrongCount, int? lastWrongTs, DateTime now) {
    if (recentWrongCount <= 0 && lastWrongTs == null) return 1;
    final ageHours = lastWrongTs == null
        ? 1e9
        : now
                .difference(DateTime.fromMillisecondsSinceEpoch(lastWrongTs))
                .inMinutes /
            60.0;
    final recency = exp(-ageHours / 36.0);
    final countBoost = min(recentWrongCount, 5) * 0.18;
    return 1 + countBoost + (0.85 * recency);
  }

  Future<List<Character>> getKnownCharacters() async {
    final db = _db!;
    final rows = await db.rawQuery('''
      SELECT s.traditional,
             MIN(d.simplified) AS simplified,
             MIN(d.pinyin) AS pinyin,
             MIN(d.definitions) AS definitions,
             MAX(f.frequency) AS frequency
      FROM list_items s
      JOIN dictionary d ON d.traditional = s.traditional
      LEFT JOIN freq f ON (d.traditional = f.char OR d.simplified = f.char)
      WHERE s.streak >= 4
      GROUP BY s.traditional
      ORDER BY COALESCE(MAX(f.frequency), 0) DESC, s.traditional
    ''');
    return rows.map(_mapToCharacter).toList();
  }

  Future<Map<int, int>> getKnownCountsByThresholds(List<int> thresholds) async {
    if (thresholds.isEmpty) return {};
    final db = _db!;
    final maxThreshold = thresholds.reduce(max);
    final rows = await db.rawQuery('''
      WITH ranked AS (
        SELECT d.traditional,
               ROW_NUMBER() OVER (ORDER BY COALESCE(f.frequency, 0) DESC, d.traditional) AS rnk
        FROM freq f
        JOIN dictionary d ON (d.traditional = f.char OR d.simplified = f.char)
        WHERE length(f.char) = 1
        GROUP BY d.traditional
      ),
      known AS (
        SELECT DISTINCT traditional FROM list_items WHERE streak >= 4
      )
      SELECT r.rnk AS rank
      FROM ranked r
      JOIN known k ON k.traditional = r.traditional
      WHERE r.rnk <= ?
      ORDER BY r.rnk
    ''', [maxThreshold]);
    final counts = <int, int>{for (final t in thresholds) t: 0};
    for (final row in rows) {
      final rank = row['rank'] as int? ?? 0;
      for (final t in thresholds) {
        if (rank <= t) counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<bool> isKnown(String traditional) async {
    final db = _db!;
    // Prefer list_items streak if present
    final streakRows = await db.query('list_items',
        columns: ['MAX(streak) as s'],
        where: 'traditional = ?',
        whereArgs: [traditional]);
    final maxStreak = streakRows.isNotEmpty && streakRows.first['s'] != null
        ? (streakRows.first['s'] as int)
        : 0;
    if (maxStreak >= 4) return true;
    // Fallback to reviews last 4
    final rows = await db.query(
      'reviews',
      columns: ['correct'],
      where: 'traditional = ?',
      whereArgs: [traditional],
      orderBy: 'ts DESC',
      limit: 4,
    );
    if (rows.length < 4) return false;
    return rows.every((r) => (r['correct'] as int) == 1);
  }

  Future<void> insertReview(String traditional, bool correct,
      {int? listId}) async {
    final db = _db!;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('reviews', {
      'traditional': traditional,
      'ts': now,
      'correct': correct ? 1 : 0,
      'list_id': listId,
    });
    final rows = await db.query('list_items',
        columns: ['list_id', 'streak'],
        where: 'traditional = ?',
        whereArgs: [traditional]);
    final batch = db.batch();
    for (final row in rows) {
      final currentStreak = (row['streak'] as int?) ?? 0;
      int newStreak = correct ? currentStreak + 1 : 0;
      int idx = newStreak;
      if (idx < 0) idx = 0;
      if (idx >= _reviewIntervals.length) {
        idx = _reviewIntervals.length - 1;
      }
      final nextDue = correct ? now + _reviewIntervals[idx] : now;
      batch.update(
        'list_items',
        {'streak': newStreak, 'next_due': nextDue},
        where: 'traditional = ? AND list_id = ?',
        whereArgs: [traditional, row['list_id']],
      );
    }
    if (!correct) {
      final priorId = await _ensurePriorMissedListId();
      await db.insert(
        'list_items',
        {
          'traditional': traditional,
          'list_id': priorId,
          'meaning': null,
          'added_ts': now,
          'streak': 0,
          'next_due': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> undoLastReview(String traditional) async {
    final db = _db!;
    final last = await db.query('reviews',
        where: 'traditional = ?',
        whereArgs: [traditional],
        orderBy: 'ts DESC',
        limit: 1);
    if (last.isEmpty) return;
    await db.delete('reviews', where: 'id = ?', whereArgs: [last.first['id']]);
    await _replayReviews(traditional);
  }

  Future<void> _replayReviews(String traditional) async {
    final db = _db!;
    final reviews = await db.query('reviews',
        columns: ['ts', 'correct'],
        where: 'traditional = ?',
        whereArgs: [traditional],
        orderBy: 'ts ASC');
    final listRows = await db.query('list_items',
        columns: ['list_id'],
        where: 'traditional = ?',
        whereArgs: [traditional]);
    int streak = 0;
    int nextDue = DateTime.now().millisecondsSinceEpoch;
    for (final rev in reviews) {
      final ts = (rev['ts'] as int?) ?? nextDue;
      final correct = (rev['correct'] as int) == 1;
      streak = correct ? streak + 1 : 0;
      int idx = streak;
      if (idx < 0) idx = 0;
      if (idx >= _reviewIntervals.length) {
        idx = _reviewIntervals.length - 1;
      }
      nextDue = correct ? ts + _reviewIntervals[idx] : ts;
    }
    final batch = db.batch();
    for (final row in listRows) {
      batch.update(
        'list_items',
        {'streak': streak, 'next_due': nextDue},
        where: 'traditional = ? AND list_id = ?',
        whereArgs: [traditional, row['list_id']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markKnown(String traditional, {int? listId}) async {
    final db = _db!;
    final targetList = listId;
    final whereArgs =
        targetList == null ? [traditional] : [traditional, targetList];
    final whereClause = targetList == null
        ? 'traditional = ?'
        : 'traditional = ? AND list_id = ?';
    await db.update(
      'list_items',
      {
        'streak': 4,
        'next_due': DateTime.now().millisecondsSinceEpoch,
      },
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<bool> _tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
        'SELECT name FROM sqlite_master WHERE type="table" AND name=?', [name]);
    return rows.isNotEmpty;
  }

  Future<Map<String, int>> getAccuracyStats() async {
    final db = _db!;
    final total = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM reviews')) ??
        0;
    final correct = Sqflite.firstIntValue(await db
            .rawQuery('SELECT COUNT(*) FROM reviews WHERE correct = 1')) ??
        0;
    return {'total': total, 'correct': correct};
  }

  Future<Map<String, int>> getAccuracyStatsForList(int listId) async {
    final db = _db!;
    final total = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM reviews WHERE list_id = ?', [listId])) ??
        0;
    final correct = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM reviews WHERE list_id = ? AND correct = 1',
            [listId])) ??
        0;
    return {'total': total, 'correct': correct};
  }

  Character _mapToCharacter(Map<String, Object?> row, {bool? isKnown}) {
    final freq = row['frequency'];
    return Character(
      traditional: row['traditional'] as String,
      simplified: row['simplified'] as String,
      pinyin: row['pinyin'] as String? ?? '',
      definitions: row['definitions'] as String? ?? '',
      frequency: freq is num ? freq.toDouble() : null,
      isKnown: isKnown,
    );
  }
}

class _StudyCandidate {
  final Character character;
  final int rank;
  final int? lastSeenTs;
  final int? lastWrongTs;
  final int recentWrongCount;
  final bool isKnown;

  _StudyCandidate({
    required this.character,
    required this.rank,
    required this.lastSeenTs,
    required this.lastWrongTs,
    required this.recentWrongCount,
    required this.isKnown,
  });
}

class _ScoredCandidate {
  final _StudyCandidate candidate;
  final double key;

  _ScoredCandidate(this.candidate, this.key);
}
