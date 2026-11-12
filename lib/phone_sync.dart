import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'phone_calendar.dart';
import 'store.dart';

/// Keeps Jarvis' events and the phone's calendar the same. What to do is decided by [CalMirror]; this part
/// reads and writes. The settings and the links live on this phone only.
class PhoneSync {
  static bool _running = false;
  static Timer? _soon;
  static int _seen = 0;

  /// {on, read: [calendar ids shown in Jarvis], writeTo: calendar id or null}
  static Map<String, dynamic> config(Store s) => jsonDecode(s.local('phoneCal') ?? '{}') as Map<String, dynamic>;

  static Future<void> saveConfig(Store s, Map<String, dynamic> cfg) => s.setLocal('phoneCal', jsonEncode(cfg));

  static bool on(Store s) => !kIsWeb && config(s)['on'] == true;

  static Map<String, dynamic> _links(Store s) => jsonDecode(s.local('phoneCalLinks') ?? '{}') as Map<String, dynamic>;

  /// Looks at the events whenever they change and syncs a few seconds later. Call once, when the app starts.
  static void watch(Store s) {
    if (kIsWeb) return;
    s.addListener(() {
      if (!on(s)) return;
      // The phone's own events arriving must not start another round.
      final now = Object.hashAll([for (final i in s.list('items')) if (CalMirror.eligible(i)) CalMirror.signature(i), s.list('items').length]);
      if (now == _seen) return;
      _seen = now;
      _soon?.cancel();
      _soon = Timer(const Duration(seconds: 4), () => unawaited(run(s)));
    });
  }

  /// One round: events changed on either side are carried over, then the phone's events are loaded for the views.
  /// Returns a short sentence for the settings page.
  static Future<String> run(Store s) async {
    if (!on(s)) return 'Off';
    if (_running) return 'Already syncing';
    if (!await PhoneCalendarApi.access()) return 'Jarvis is not allowed to use the calendar';
    _running = true;
    try {
      final cfg = config(s);
      final links = _links(s);
      final phone = <int, Map<String, dynamic>>{};
      for (final l in links.values) {
        final ev = (l as Map)['ev'];
        if (l['off'] == true || ev is! int) continue;
        final e = await PhoneCalendarApi.event(ev);
        if (e != null) phone[ev] = e;
      }
      final writeTo = cfg['writeTo'] as int?;
      final ops = CalMirror.plan(items: s.list('items'), links: links, phone: phone, canWrite: writeTo != null);
      var changedItems = false;
      for (final op in ops) {
        final it = op.item;
        final key = '${it?['id']}';
        switch (op.kind) {
          case 'create':
            final ev = await PhoneCalendarApi.insert(writeTo!, CalMirror.toPhone(it!));
            if (ev > 0) await _link(links, key, it, ev);
          case 'update':
            if (await PhoneCalendarApi.update(op.ev!, CalMirror.toPhone(it!))) await _link(links, key, it, op.ev!);
          case 'pull':
            it!.addAll(CalMirror.fromPhone(phone[op.ev!]!));
            await s.syncRecord('items', it);
            await _link(links, key, it, op.ev!);
            changedItems = true;
          case 'forget':
            links[key] = {'off': true};
          case 'remove':
            await PhoneCalendarApi.delete(op.ev!);
            links.removeWhere((_, l) => (l as Map)['ev'] == op.ev);
        }
      }
      await s.setLocal('phoneCalLinks', jsonEncode(links));
      if (changedItems) s.save();
      final shown = await _refresh(s, cfg, links);
      final carried = ops.length;
      return '${carried == 0 ? 'Up to date' : 'Carried over $carried change${carried == 1 ? '' : 's'}'}, $shown from the phone';
    } on Exception catch (e) {
      return 'Could not sync: $e';
    } finally {
      _running = false;
    }
  }

  /// Notes that both sides now match, reading the phone event back so what it normalised does not look like a change.
  static Future<void> _link(Map<String, dynamic> links, String key, Rec item, int ev) async {
    final back = await PhoneCalendarApi.event(ev);
    if (back == null) return;
    links[key] = {'ev': ev, 'jsig': CalMirror.signature(item), 'psig': CalMirror.phoneSig(back)};
  }

  /// Loads the phone's events for the calendar views: a month back to a year ahead, without the ones Jarvis wrote.
  static Future<int> _refresh(Store s, Map<String, dynamic> cfg, Map<String, dynamic> links) async {
    final ids = [for (final id in (cfg['read'] as List?) ?? const []) id as int];
    final mine = {for (final l in links.values) (l as Map)['ev']};
    final now = DateTime.now();
    final all = await PhoneCalendarApi.instances(
      DateTime(now.year, now.month - 1, now.day),
      DateTime(now.year + 1, now.month, now.day),
      ids,
    );
    final items = [for (final e in all) if (!mine.contains(e['ev'])) CalMirror.external(e)];
    s.setExternal(items);
    return items.length;
  }

  /// Takes the phone's events out of the views.
  static void clear(Store s) => s.setExternal(const []);
}
