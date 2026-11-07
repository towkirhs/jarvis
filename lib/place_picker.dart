import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'haptics.dart';
import 'native.dart';
import 'store.dart';

/// Asks for location so places work in the background: "while using the app", then "all the time".
/// Returns true when both are given.
Future<bool> ensureLocation(BuildContext context) async {
  var a = await Native.locationAccess();
  if (a['fine'] == true && a['background'] == true) return true;
  if (!context.mounted) return false;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Allow location'),
      content: Text(a['fine'] == true
          ? 'For places to work while Jarvis is closed, choose "Allow all the time" on the next screen. '
              'Your location stays on the phone; it is only compared with your places.'
          : 'Jarvis needs your location to know when you arrive at or leave a place. It stays on the phone. '
              'Android will ask twice: first while using the app, then all the time.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
      ],
    ),
  );
  if (go != true) return false;
  await Native.requestLocation();
  await Future<void>.delayed(const Duration(seconds: 1));
  a = await Native.locationAccess();
  return a['fine'] == true && a['background'] == true;
}

/// Picks one of your places, or makes a new one on the map. Returns its id.
Future<int?> pickPlace(BuildContext context, Store s, {int? current}) => showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final places = s.list('places');
        return SafeArea(
          child: ListView(shrinkWrap: true, children: [
            for (final p in places)
              ListTile(
                leading: Icon(p['id'] == current ? Icons.radio_button_checked : Icons.place_outlined),
                title: Text(p['name'] as String),
                subtitle: Text('Within ${p['radius'] ?? 200} m'),
                trailing: IconButton(
                  tooltip: 'Edit on the map',
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  onPressed: () async {
                    final id = await Navigator.of(ctx).push<int>(
                      MaterialPageRoute(builder: (_) => PlacePickerPage(store: s, place: p)),
                    );
                    if (id != null && ctx.mounted) Navigator.pop(ctx, id);
                  },
                ),
                onTap: () => Navigator.pop(ctx, p['id'] as int),
              ),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text('New place on the map'),
              onTap: () async {
                final id = await Navigator.of(ctx).push<int>(MaterialPageRoute(builder: (_) => PlacePickerPage(store: s)));
                if (ctx.mounted) Navigator.pop(ctx, id);
              },
            ),
          ]),
        );
      },
    );

/// A place on a map: search an address, tap the map, or use where you are. Saves it to your places.
class PlacePickerPage extends StatefulWidget {
  const PlacePickerPage({super.key, required this.store, this.place});
  final Store store;
  final Rec? place;

  @override
  State<PlacePickerPage> createState() => _PlacePickerPageState();
}

class _PlacePickerPageState extends State<PlacePickerPage> {
  Store get s => widget.store;
  final _map = MapController();
  late final _name = TextEditingController(text: widget.place?['name'] as String? ?? '');
  final _search = TextEditingController();
  LatLng? _pin;
  late double _radius = ((widget.place?['radius'] as num?) ?? 200).toDouble();
  List<Map<String, dynamic>> _found = [];
  String? _note;

  // Dhaka, until there is a better guess.
  static const _start = LatLng(23.8103, 90.4125);

  @override
  void initState() {
    super.initState();
    final p = widget.place;
    if (p != null) _pin = LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _moveTo(LatLng p, {double zoom = 16}) {
    setState(() => _pin = p);
    _map.move(p, zoom);
  }

  Future<void> _here() async {
    var a = await Native.locationAccess();
    if (a['fine'] != true) {
      await Native.requestLocation();
      await Future<void>.delayed(const Duration(seconds: 1));
      a = await Native.locationAccess();
    }
    setState(() => _note = 'Finding you…');
    final h = await Native.here();
    if (!mounted) return;
    if (h == null) {
      Haptics.reject();
      setState(() => _note = a['fine'] == true ? 'Could not find you. Is location on?' : 'Allow location to use this.');
      return;
    }
    Haptics.tap();
    setState(() => _note = null);
    _moveTo(LatLng(h.$1, h.$2), zoom: 17);
  }

  /// Address search with OpenStreetMap's Nominatim.
  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _note = 'Searching…';
      _found = [];
    });
    try {
      final r = await http.get(
        Uri.https('nominatim.openstreetmap.org', '/search', {'q': q, 'format': 'json', 'limit': '6'}),
        headers: {'User-Agent': 'Jarvis personal assistant app (github.com/towkirhs/jarvis)'},
      );
      final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _found = list;
        _note = list.isEmpty ? 'Nothing found. Try another name, or tap the map.' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _note = 'Search did not work (offline?). Tap the map instead.');
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (_pin == null || name.isEmpty) {
      Haptics.reject();
      setState(() => _note = _pin == null ? 'Put the pin on the place first.' : 'Give the place a name.');
      return;
    }
    final fields = {'name': name, 'lat': _pin!.latitude, 'lng': _pin!.longitude, 'radius': _radius.round()};
    var p = widget.place;
    if (p == null) {
      p = {'id': s.nextId(), ...fields};
      s.list('places').add(p);
    } else {
      p.addAll(fields);
    }
    s.save();
    Haptics.success();
    Navigator.pop(context, p['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place == null ? 'New place' : 'Edit place'),
        actions: [
          if (widget.place != null)
            IconButton(
              tooltip: 'Delete place',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                Haptics.warn();
                s.list('places').removeWhere((p) => p['id'] == widget.place!['id']);
                s.save();
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            decoration: InputDecoration(
              hintText: 'Search an address or a place',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _find),
            ),
          ),
        ),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _pin ?? _start,
                initialZoom: _pin == null ? 12 : 16,
                onTap: (_, p) {
                  Haptics.tick();
                  setState(() {
                    _pin = p;
                    _found = [];
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.towkirhs.jarcis',
                ),
                if (_pin != null)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: _pin!,
                      radius: _radius,
                      useRadiusInMeter: true,
                      color: scheme.primary.withValues(alpha: 0.18),
                      borderColor: scheme.primary,
                      borderStrokeWidth: 2,
                    ),
                  ]),
                if (_pin != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _pin!,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on, size: 40, color: scheme.primary),
                    ),
                  ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
              ],
            ),
            if (_found.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                top: 0,
                child: Card(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final f in _found)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text('${f['display_name']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Haptics.tap();
                          if (_name.text.trim().isEmpty) _name.text = '${f['name'] ?? ''}';
                          setState(() => _found = []);
                          _moveTo(LatLng(double.parse('${f['lat']}'), double.parse('${f['lon']}')));
                        },
                      ),
                  ]),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 56,
              child: FloatingActionButton.small(
                heroTag: 'here',
                tooltip: 'Where I am',
                onPressed: _here,
                child: const Icon(Icons.my_location),
              ),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_note!, style: tt.bodySmall)),
              Text(_pin == null ? 'Tap the map, search, or use where you are.' : 'Goes off within ${_radius.round()} m',
                  style: tt.labelLarge),
              Slider(
                value: _radius,
                min: 100,
                max: 1000,
                divisions: 18,
                label: '${_radius.round()} m',
                onChanged: (v) => setState(() => _radius = v),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'Name, like Home or Office'),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
