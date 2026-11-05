import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'store.dart';
import 'sync_merge.dart';

/// End-to-end encrypted sync through a private GitHub Gist. The passphrase never leaves the phone,
/// and GitHub only ever sees encrypted bytes.
class Sync {
  static const _file = 'jarvis-sync.json';
  static const _description = 'Jarvis encrypted sync';
  static const iterations = 100000;
  static final _aes = AesGcm.with256bits();

  static bool enabled(Store s) => s.local('sync_token') != null && s.local('sync_key') != null;

  static DateTime? _lastPull;
  static bool _busy = false;

  /// The key from the passphrase and salt (slow on purpose, so guessing passphrases is slow).
  static Future<List<int>> deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
    return key.extractBytes();
  }

  static Future<String> encrypt(Map<String, dynamic> state, List<int> key, List<int> salt) async {
    final plain = GZipEncoder().encode(utf8.encode(jsonEncode(state)))!;
    final box = await _aes.encrypt(plain, secretKey: SecretKey(key));
    return jsonEncode({
      'v': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
      'stamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Throws SecretBoxAuthenticationError when the passphrase is wrong.
  static Future<Map<String, dynamic>> decrypt(String envelope, List<int> key) async {
    final e = jsonDecode(envelope) as Map<String, dynamic>;
    final box = SecretBox(base64Decode(e['data'] as String),
        nonce: base64Decode(e['nonce'] as String), mac: Mac(base64Decode(e['mac'] as String)));
    final plain = await _aes.decrypt(box, secretKey: SecretKey(key));
    return jsonDecode(utf8.decode(GZipDecoder().decodeBytes(plain))) as Map<String, dynamic>;
  }

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
      };

  static Exception _error(http.Response r) {
    if (r.statusCode == 401) return Exception('GitHub did not accept the token.');
    if (r.statusCode == 403 || r.statusCode == 404) return Exception('The token needs the "gist" permission.');
    return Exception('GitHub error ${r.statusCode}');
  }

  /// Finds the existing sync gist (made on another device), or null.
  static Future<(String, String)?> _findGist(String token) async {
    final r = await http.get(Uri.parse('https://api.github.com/gists?per_page=100'), headers: _headers(token));
    if (r.statusCode != 200) throw _error(r);
    for (final g in jsonDecode(r.body) as List) {
      if (g['description'] == _description && (g['files'] as Map).containsKey(_file)) {
        return (g['id'] as String, await _download(token, g['id'] as String));
      }
    }
    return null;
  }

  static Future<String> _download(String token, String id) async {
    final r = await http.get(Uri.parse('https://api.github.com/gists/$id'), headers: _headers(token));
    if (r.statusCode != 200) throw _error(r);
    final f = (jsonDecode(r.body)['files'] as Map)[_file] as Map;
    if (f['truncated'] == true) {
      final raw = await http.get(Uri.parse(f['raw_url'] as String));
      return raw.body;
    }
    return f['content'] as String;
  }

  static Future<String> _upload(String token, String? id, String content) async {
    final body = jsonEncode({
      'description': _description,
      'public': false,
      'files': {
        _file: {'content': content},
      },
    });
    final r = id == null
        ? await http.post(Uri.parse('https://api.github.com/gists'), headers: _headers(token), body: body)
        : await http.patch(Uri.parse('https://api.github.com/gists/$id'), headers: _headers(token), body: body);
    if (r.statusCode != 200 && r.statusCode != 201) throw _error(r);
    return jsonDecode(r.body)['id'] as String;
  }

  /// Turns sync on with a GitHub token and passphrase. Joins the existing synced copy if there is one
  /// (the passphrase must then match), otherwise uploads this device's data.
  static Future<String> setUp(Store s, String token, String passphrase) async {
    final found = await _findGist(token);
    final slot = 1 + Random.secure().nextInt(99);
    if (found != null) {
      final env = jsonDecode(found.$2) as Map<String, dynamic>;
      final salt = base64Decode(env['salt'] as String);
      final key = await deriveKey(passphrase, salt);
      Map<String, dynamic> remote;
      try {
        remote = await decrypt(found.$2, key);
      } catch (_) {
        throw Exception('That passphrase does not open your synced data. Use the one you set on your other device.');
      }
      await _saveSetup(s, token, found.$1, key, salt, slot);
      final hasData = ['items', 'captures', 'tx', 'entries', 'habits'].any((c) => s.list(c).isNotEmpty);
      final merged = SyncMerge.merge(s.state, remote, localChanged: hasData, slot: slot);
      await s.replaceState(merged);
      await _push(s);
      return 'Joined your synced Jarvis and merged this device into it.';
    }
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await deriveKey(passphrase, salt);
    await _saveSetup(s, token, null, key, salt, slot);
    s.state['next'] = SyncMerge.merge(s.state, const {}, localChanged: true, slot: slot)['next'];
    s.save();
    await _push(s);
    return 'Sync is on. Use the same token and passphrase on your other devices.';
  }

  static Future<void> _saveSetup(Store s, String token, String? gist, List<int> key, List<int> salt, int slot) async {
    await s.setLocal('sync_token', token);
    await s.setLocal('sync_gist', gist);
    await s.setLocal('sync_key', base64Encode(key));
    await s.setLocal('sync_salt', base64Encode(salt));
    await s.setLocal('sync_slot', '$slot');
  }

  static Future<void> turnOff(Store s) async {
    for (final k in ['sync_token', 'sync_gist', 'sync_key', 'sync_salt', 'sync_slot', 'sync_stamp', 'sync_at']) {
      await s.setLocal(k, null);
    }
  }

  static Future<void> _push(Store s) async {
    final at = s.changes;
    final key = base64Decode(s.local('sync_key')!);
    final salt = base64Decode(s.local('sync_salt')!);
    final env = await encrypt(s.state, key, salt);
    final id = await _upload(s.local('sync_token')!, s.local('sync_gist'), env);
    await s.setLocal('sync_gist', id);
    await s.setLocal('sync_stamp', '${(jsonDecode(env) as Map)['stamp']}');
    await s.setLocal('sync_at', '${DateTime.now().millisecondsSinceEpoch}');
    await s.clearDirty(at);
  }

  /// Pulls changes from other devices and pushes this device's. Cheap to call often: it does nothing
  /// unless something changed here or it has been 10 minutes since the last check.
  static Future<String?> run(Store s, {bool force = false}) async {
    if (!enabled(s) || _busy) return null;
    final stale = _lastPull == null || DateTime.now().difference(_lastPull!) > const Duration(minutes: 10);
    if (!force && !s.dirty && !stale) return null;
    _busy = true;
    try {
      final gist = s.local('sync_gist');
      if (gist == null) {
        await _push(s);
        return 'Synced.';
      }
      final env = await _download(s.local('sync_token')!, gist);
      _lastPull = DateTime.now();
      final stamp = '${(jsonDecode(env) as Map)['stamp']}';
      if (stamp != s.local('sync_stamp')) {
        final remote = await decrypt(env, base64Decode(s.local('sync_key')!));
        final slot = int.parse(s.local('sync_slot') ?? '1');
        final hadChanges = s.dirty;
        await s.replaceState(SyncMerge.merge(s.state, remote, localChanged: hadChanges, slot: slot));
        if (hadChanges) {
          await _push(s);
        } else {
          await s.setLocal('sync_stamp', stamp);
          await s.setLocal('sync_at', '${DateTime.now().millisecondsSinceEpoch}');
          await s.clearDirty(s.changes);
        }
      } else if (s.dirty) {
        await _push(s);
      } else {
        await s.setLocal('sync_at', '${DateTime.now().millisecondsSinceEpoch}');
      }
      return 'Synced.';
    } finally {
      _busy = false;
    }
  }

  static DateTime? lastSynced(Store s) {
    final at = int.tryParse(s.local('sync_at') ?? '');
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }
}
