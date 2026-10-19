import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';

import 'task_record.dart';

class LocalWorkStore {
  factory LocalWorkStore(String owner, {Database? database, SecretKey? key}) =>
      database != null || key != null
      ? LocalWorkStore._(owner, database: database, key: key)
      : _stores.putIfAbsent(owner, () => LocalWorkStore._(owner));
  LocalWorkStore._(this.owner, {this._database, this._key})
    : _barrier = _cleanups[owner];
  static final _stores = <String, LocalWorkStore>{};
  static final _cleanups = <String, Future<void>>{};
  final Future<void>? _barrier;
  final String owner;
  Database? _database;
  SecretKey? _key;
  Future<SecretKey>? _keyLoading;
  Future<Database>? _opening;
  bool _closed = false;
  final _cipher = AesGcm.with256bits();
  static const _secure = FlutterSecureStorage();
  Future<Database> get _db async {
    await _barrier;
    return _database ??= await (_opening ??= _open());
  }

  Future<Database> _open() async => openDatabase(
    paths.join(await getDatabasesPath(), 'janitra_work_v1.db'),
    version: 1,
    onCreate: (db, version) => db.execute(
      'CREATE TABLE work_cache(owner TEXT NOT NULL,bucket TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(owner,bucket))',
    ),
  );
  Future<SecretKey> get _secret async {
    if (_closed) throw StateError('Local session ended');
    if (_key != null) return _key!;
    return _keyLoading ??= _loadSecret().whenComplete(() => _keyLoading = null);
  }

  Future<SecretKey> _loadSecret() async {
    final stored = await _secure.read(key: 'janitra.work.key.$owner');
    if (stored != null) return _key = SecretKey(base64Decode(stored));
    final created = await _cipher.newSecretKey();
    await _secure.write(
      key: 'janitra.work.key.$owner',
      value: base64Encode(await created.extractBytes()),
    );
    return _key = created;
  }

  Future<void> put(String bucket, Map<String, dynamic> data) async {
    final secret = await _secret;
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: secret,
      aad: utf8.encode('$owner/$bucket'),
    );
    final db = await _db;
    if (_closed) throw StateError('Local session ended');
    await db.insert('work_cache', {
      'owner': owner,
      'bucket': bucket,
      'payload': Uint8List.fromList(box.concatenation()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> get(String bucket) async {
    if (_closed) throw StateError('Local session ended');
    final rows = await (await _db).query(
      'work_cache',
      where: 'owner=? AND bucket=?',
      whereArgs: [owner, bucket],
    );
    if (rows.isEmpty) return null;
    final box = SecretBox.fromConcatenation(
      rows.single['payload'] as Uint8List,
      nonceLength: 12,
      macLength: 16,
    );
    final plain = await _cipher.decrypt(
      box,
      secretKey: await _secret,
      aad: utf8.encode('$owner/$bucket'),
    );
    if (_closed) throw StateError('Local session ended');
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  Future<void> remove(String bucket) async => (await _db).delete(
    'work_cache',
    where: 'owner=? AND bucket=?',
    whereArgs: [owner, bucket],
  );
  Future<void> saveDraft(WorkDraft draft) {
    if (draft.task.userId != owner) {
      throw StateError('Draft belongs to another account');
    }
    return put('draft:${draft.task.id}', draft.toJson());
  }

  Future<WorkDraft?> draft(String id) async {
    final data = await get('draft:$id');
    return data == null ? null : WorkDraft.fromJson(data);
  }

  Future<List<WorkDraft>> drafts() async {
    final rows = await (await _db).query(
      'work_cache',
      columns: ['bucket'],
      where: 'owner=? AND bucket LIKE ?',
      whereArgs: [owner, 'draft:%'],
    );
    final result = <WorkDraft>[];
    for (final row in rows) {
      final data = await get(row['bucket'] as String);
      if (data != null) result.add(WorkDraft.fromJson(data));
    }
    return result;
  }

  Future<void> clear() async {
    _closed = true;
    try {
      await _keyLoading;
    } catch (_) {}
    try {
      await (await _db).delete(
        'work_cache',
        where: 'owner=?',
        whereArgs: [owner],
      );
    } finally {
      try {
        await _secure.delete(key: 'janitra.work.key.$owner');
      } finally {
        _key = null;
        if (identical(_stores[owner], this)) _stores.remove(owner);
      }
    }
  }

  Future<void> seal() {
    _closed = true;
    if (identical(_stores[owner], this)) _stores.remove(owner);
    final cleanup = _seal();
    _cleanups[owner] = cleanup.catchError((Object _) {});
    return cleanup;
  }

  Future<void> _seal() async {
    try {
      await _keyLoading;
    } catch (_) {}
    try {
      final db = await _db;
      await db.delete(
        'work_cache',
        where: 'owner=? AND bucket NOT LIKE ?',
        whereArgs: [owner, 'draft:%'],
      );
    } finally {
      _key = null;
      if (identical(_stores[owner], this)) _stores.remove(owner);
    }
  }
}
