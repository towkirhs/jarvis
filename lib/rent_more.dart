import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'haptics.dart';
import 'rent.dart';
import 'rent_page.dart' show RoomPage;
import 'store.dart';

String _day(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${Rent.monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}

const _statusNames = {'paid': 'Paid', 'partial': 'Partly paid', 'due': 'Due'};

Color _statusColor(ColorScheme c, String status) => switch (status) {
      'paid' => c.primary,
      'partial' => c.tertiary,
      _ => c.error,
    };

/// A small coloured label: "• Paid".
Widget statusPill(BuildContext context, String label, Color color) => Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );

/// A label on the left, a value on the right.
Widget _row(BuildContext context, String left, String right, {bool strong = false, Color? color}) {
  final tt = Theme.of(context).textTheme;
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(left, style: strong ? tt.titleSmall : tt.bodyMedium?.copyWith(color: muted))),
      Text(right, style: (strong ? tt.titleSmall : tt.bodyMedium)?.copyWith(color: color)),
    ]),
  );
}

List<Rec> _rooms(Store s) => s.list('rooms').toList()..sort((a, b) => '${a['number']}'.compareTo('${b['number']}'));

// ---------- all bills ----------

/// Every room's bill for one month, filtered by tenant and by whether it is paid.
class AllBillsPage extends StatefulWidget {
  const AllBillsPage({super.key, required this.store});
  final Store store;

  @override
  State<AllBillsPage> createState() => _AllBillsPageState();
}

class _AllBillsPageState extends State<AllBillsPage> {
  Store get s => widget.store;
  String month = Rent.key(DateTime.now());
  int? room; // null = all tenants
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final now = DateTime.now();
        final rooms = _rooms(s);
        final pays = s.list('rentPays');
        final bills = s.list('roomBills');
        final first = rooms.isEmpty
            ? Rent.key(now)
            : rooms.map((r) => r['start'] as String).reduce((a, b) => a.compareTo(b) < 0 ? a : b);
        // Rooms that were let in this month, with their bill.
        final lines = [
          for (final r in rooms)
            if ((r['start'] as String).compareTo(month) <= 0) (room: r, line: Rent.month(r, month, pays, bills)),
        ];
        final counts = {for (final k in _statusNames.keys) k: lines.where((l) => Rent.status(l.line) == k).length};
        final shown = lines
            .where((l) => room == null || l.room['id'] == room)
            .where((l) => filter == 'all' || Rent.status(l.line) == filter)
            .toList();
        final toCollect = lines.fold<num>(0, (a, l) => a + (l.line.left > 0 ? l.line.left : 0));
        final collected = lines.fold<num>(0, (a, l) => a + l.line.paid);
        return Scaffold(
          appBar: AppBar(
            title: const Text('All bills'),
            actions: [
              IconButton(
                tooltip: 'Earlier month',
                icon: const Icon(Icons.chevron_left),
                onPressed: month.compareTo(first) <= 0 ? null : () => setState(() => month = Rent.shift(month, -1)),
              ),
              IconButton(
                tooltip: 'Later month',
                icon: const Icon(Icons.chevron_right),
                onPressed: month.compareTo(Rent.key(now)) >= 0 ? null : () => setState(() => month = Rent.shift(month, 1)),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(Rent.name(month), style: tt.headlineSmall),
              Text('${s.money(collected)} collected, ${s.money(toCollect)} still to collect',
                  style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: room,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All tenants')),
                  for (final r in rooms) DropdownMenuItem(value: r['id'] as int, child: Text('Room ${r['number']}, ${r['tenant']}')),
                ],
                onChanged: (v) => setState(() => room = v),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in ['all', ..._statusNames.keys])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(k == 'all' ? 'All ${lines.length}' : '${_statusNames[k]} ${counts[k]}'),
                        selected: filter == k,
                        onSelected: (_) {
                          Haptics.segment();
                          setState(() => filter = k);
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    rooms.isEmpty ? 'Add a room first.' : 'No bills here for ${Rent.name(month)}.',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final l in shown) _billCard(context, l.room, l.line),
            ],
          ),
        );
      },
    );
  }

  Widget _billCard(BuildContext context, Rec r, MonthLine x) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final status = Rent.status(x);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReceiptPage(store: s, roomId: r['id'] as int, month: x.month)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Room ${r['number']}', style: tt.titleMedium),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${r['tenant']}',
                    overflow: TextOverflow.ellipsis, style: tt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              statusPill(context, _statusNames[status]!, _statusColor(scheme, status)),
            ]),
            const SizedBox(height: 8),
            _row(context, 'Rent', s.money(x.rent)),
            _row(context, 'Utilities', s.money(x.billTotal)),
            if (x.carried != 0)
              _row(context, x.carried > 0 ? 'Owed from before' : 'Paid ahead before', s.money(x.carried.abs())),
            _row(context, 'Total due', s.money(x.toPay), strong: true),
            if (x.paid > 0) _row(context, 'Paid', s.money(x.paid), color: scheme.primary),
            if (status == 'partial') _row(context, 'Left', s.money(x.left), strong: true, color: scheme.error),
          ]),
        ),
      ),
    );
  }
}

// ---------- receipt ----------

/// One room's bill for one month, laid out to save as an image or send as text.
class ReceiptPage extends StatefulWidget {
  const ReceiptPage({super.key, required this.store, required this.roomId, required this.month});
  final Store store;
  final int roomId;
  final String month;

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  Store get s => widget.store;
  final _paper = GlobalKey();

  void _say(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  String get _landlord => ((s.settings['landlordName'] as String?) ?? '').trim();

  String get _address => ((s.settings['landlordAddress'] as String?) ?? '').trim();

  Future<void> _setLandlord() async {
    final c = TextEditingController(text: _landlord);
    final a = TextEditingController(text: _address);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You, on receipts'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name')),
          const SizedBox(height: 12),
          TextField(controller: a, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Address of the house')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    s.settings['landlordName'] = c.text.trim();
    s.settings['landlordAddress'] = a.text.trim();
    s.save();
  }

  /// The receipt as a picture, sharp enough to print.
  Future<Uint8List> _png() async {
    final boundary = _paper.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  /// Opens the phone's print screen with the receipt on an A4 page (it can also save a PDF).
  Future<void> _print(Rec r) async {
    try {
      final picture = pw.MemoryImage(await _png());
      final doc = pw.Document()
        ..addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(36),
          build: (_) => pw.Align(alignment: pw.Alignment.topCenter, child: pw.Image(picture, fit: pw.BoxFit.contain)),
        ));
      await Printing.layoutPdf(name: 'receipt-room-${r['number']}-${widget.month}', onLayout: (_) => doc.save());
    } catch (e) {
      if (mounted) _say('Could not print: $e');
    }
  }

  String _text(Rec r, MonthLine x) {
    final b = StringBuffer()
      ..writeln('Rent receipt, ${Rent.name(x.month)}')
      ..writeln('Room ${r['number']}: ${r['tenant']}')
      ..writeln(_landlord.isEmpty ? '' : 'From $_landlord')
      ..writeln()
      ..writeln('Rent: ${s.money(x.rent)}');
    for (final bill in x.bills) {
      b.writeln('${Rent.billKinds[bill['kind']] ?? 'Bill'}: ${s.money(bill['amount'] as num)}');
    }
    if (x.carried != 0) b.writeln('${x.carried > 0 ? 'Owed from before' : 'Paid ahead before'}: ${s.money(x.carried.abs())}');
    b.writeln('Total due: ${s.money(x.toPay)}');
    for (final p in x.payments) {
      b.writeln('Paid ${_day(p['paidAt'] as int)}${p['method'] == null ? '' : ' by ${p['method']}'}: ${s.money(p['amount'] as num)}');
    }
    b.writeln(x.left > 0 ? 'Left to pay: ${s.money(x.left)}' : (x.left < 0 ? 'Paid ahead: ${s.money(-x.left)}' : 'Fully paid'));
    return b.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Future<void> _saveImage(Rec r) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save receipt',
        fileName: 'receipt-room-${r['number']}-${widget.month}.png',
        bytes: await _png(),
      );
      if (mounted && (kIsWeb || path != null)) _say('Receipt saved.');
    } catch (e) {
      if (mounted) _say('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final r = s.byId('rooms', widget.roomId);
        if (r == null) return const Scaffold(body: Center(child: Text('This room was deleted.')));
        final x = Rent.month(r, widget.month, s.list('rentPays'), s.list('roomBills'));
        final status = Rent.status(x);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Receipt'),
            actions: [
              IconButton(
                tooltip: 'Open the room',
                icon: const Icon(Icons.meeting_room_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RoomPage(store: s, roomId: widget.roomId))),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              RepaintBoundary(
                key: _paper,
                child: _ReceiptPaper(
                  landlord: _landlord,
                  address: _address,
                  tenant: '${r['tenant']}',
                  room: 'Room ${r['number']}',
                  number: 'R${r['number']}-${x.month.replaceAll('-', '')}',
                  paidAt: x.payments.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(x.payments.last['paidAt'] as int),
                  methods: {for (final p in x.payments) '${p['method'] ?? 'Cash'}'},
                  period: Rent.name(x.month),
                  amount: s.money(x.paid),
                  notes: [
                    ('Rent', s.money(x.rent)),
                    for (final b in x.bills)
                      (
                        '${Rent.billKinds[b['kind']] ?? 'Bill'}, ${Rent.name(Rent.shift(x.month, -1), short: true)}'
                            '${b['to'] != null ? ' (${b['from']} to ${b['to']}, ${s.money(b['rate'] as num)} a unit)' : ''}',
                        s.money(b['amount'] as num),
                      ),
                    if (x.carried != 0) (x.carried > 0 ? 'Owed from before' : 'Paid ahead before', s.money(x.carried.abs())),
                    ('Total due', s.money(x.toPay)),
                    (x.left > 0 ? 'Left to pay' : (x.left < 0 ? 'Paid ahead' : 'Fully paid'), s.money(x.left.abs())),
                  ],
                  payments: [
                    for (final p in x.payments) ('${_day(p['paidAt'] as int)}, ${p['method'] ?? 'Cash'}', s.money(p['amount'] as num)),
                  ],
                  status: _statusNames[status]!,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _setLandlord,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(_landlord.isEmpty ? 'Add your name and address' : 'Change your name and address'),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _print(r),
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print or save as PDF'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _saveImage(r),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Save as image'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _text(r, x)));
                  Haptics.tap();
                  if (mounted) _say('Copied. Paste it into WhatsApp or SMS.');
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy as text'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The receipt as a sheet of paper, laid out like a printed rent receipt form: who is paid, who pays,
/// the payment, and notes with a signature line. Always black on white, whatever the app's theme, since it is printed.
class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.landlord, required this.address, required this.tenant, required this.room, required this.number,
    required this.paidAt, required this.methods, required this.period, required this.amount, required this.notes,
    required this.payments, required this.status,
  });
  final String landlord, address, tenant, room, number, period, amount, status;
  final DateTime? paidAt;
  final Set<String> methods;
  final List<(String, String)> notes;
  final List<(String, String)> payments;

  static const _ink = Color(0xFF1B1B1B);
  static const _band = Color(0xFF0B7285); // the app's kingfisher teal
  static const _fill = Color(0xFFF2F6FC);
  static const _line = BorderSide(color: _ink, width: 0.8);

  Widget _head(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: const BoxDecoration(border: Border(bottom: _line)),
        child: Text(text, style: const TextStyle(color: _ink, fontSize: 13, letterSpacing: 0.4)),
      );

  Widget _field(String label, String value, {bool last = false}) => Container(
        decoration: BoxDecoration(border: last ? null : const Border(bottom: _line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 84,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(border: Border(right: _line)),
              child: Text(label, style: const TextStyle(color: _ink, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Container(
                color: _fill,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(value, style: const TextStyle(color: _ink, fontSize: 11.5)),
              ),
            ),
          ]),
        ),
      );

  Widget _box(List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(border: Border.all(color: _ink, width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _tick(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(border: Border.all(color: _ink, width: 0.8)),
            child: methods.contains(label) ? const Icon(Icons.check, size: 11, color: _ink) : null,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: _ink, fontSize: 10.5)),
        ]),
      );

  Widget _pair((String, String) p, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(p.$1, style: TextStyle(color: _ink, fontSize: 10.5, fontWeight: strong ? FontWeight.w700 : null))),
          const SizedBox(width: 6),
          Text(p.$2, style: TextStyle(color: _ink, fontSize: 10.5, fontWeight: strong ? FontWeight.w700 : null)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final at = paidAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return Container(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: _band,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Row(children: [
            const Expanded(child: Text('Rent Receipt', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700))),
            Text(status, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _box([_head('PAYEE INFORMATION'), _field('NAME:', landlord), _field('ADDRESS:', address, last: true)]),
            _box([_head('PAYER INFORMATION'), _field('NAME:', tenant), _field('ADDRESS:', address.isEmpty ? room : '$room, $address', last: true)]),
            _box([
              _head('PAYMENT DETAILS'),
              _field('RECEIPT #:', number),
              _field('DATE:', at == null ? '' : '${at.day} ${Rent.monthNames[at.month - 1]} ${at.year}'),
              _field('TIME:', at == null || (at.hour == 0 && at.minute == 0) ? '' : '${two(at.hour)}:${two(at.minute)}'),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(border: Border(right: _line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final m in {...Rent.payMethods, ...methods}) _tick(m),
                      ]),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _pair(('RENT FOR THE PERIOD:', period), strong: true),
                        _pair(('AMOUNT:', amount), strong: true),
                        _pair(('PROPERTY TYPE:', 'Room')),
                        _pair(('LOCATION:', room)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
            _box([
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(border: Border(right: _line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _head('IMPORTANT NOTES'),
                        Container(
                          width: double.infinity,
                          color: _fill,
                          padding: const EdgeInsets.all(8),
                          child: Column(children: [
                            for (var k = 0; k < notes.length; k++) _pair(notes[k], strong: k >= notes.length - 2),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _head('DESCRIPTION'),
                      Container(
                        width: double.infinity,
                        color: _fill,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Column(children: [
                          if (payments.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No payment yet.', style: TextStyle(color: _ink, fontSize: 10.5))),
                          for (final p in payments) _pair(p),
                        ]),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: const BoxDecoration(border: Border(top: _line, bottom: _line)),
                        child: Text('PERSON RESPONSIBLE${landlord.isEmpty ? '' : ': $landlord'}',
                            style: const TextStyle(color: _ink, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: Text('SIGNATURE:', style: TextStyle(color: _ink, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                      Container(margin: const EdgeInsets.fromLTRB(16, 34, 16, 12), height: 1.2, color: _ink),
                    ]),
                  ),
                ]),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ---------- meetings ----------

/// Meetings with tenants. Each is a calendar event, so it reminds you and shows in the calendar.
class MeetingsPage extends StatefulWidget {
  const MeetingsPage({super.key, required this.store});
  final Store store;

  @override
  State<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends State<MeetingsPage> {
  Store get s => widget.store;
  String filter = 'upcoming';
  String query = '';

  String _members(Rec m) {
    final ids = ((m['rooms'] as List?) ?? const []).cast<int>();
    if (ids.isEmpty) return 'All tenants';
    return ids.map((id) => s.byId('rooms', id)).whereType<Rec>().map((r) => '${r['tenant']}').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final now = DateTime.now();
        final all = s.list('items').where((i) => i['meeting'] == true && i['status'] != 'cancelled' && i['when'] is int).toList();
        final upcoming = all.where((m) => !Rent.meetingDone(m, now)).toList()
          ..sort((a, b) => (a['when'] as int).compareTo(b['when'] as int));
        final done = all.where((m) => Rent.meetingDone(m, now)).toList()
          ..sort((a, b) => (b['when'] as int).compareTo(a['when'] as int));
        final q = query.trim().toLowerCase();
        final shown = (switch (filter) { 'upcoming' => upcoming, 'done' => done, _ => [...upcoming, ...done] })
            .where((m) => q.isEmpty || '${m['title']} ${m['where'] ?? ''} ${m['desc'] ?? ''} ${_members(m)}'.toLowerCase().contains(q))
            .toList();
        Widget tile(String key, String label, int n) {
          final on = filter == key;
          return Expanded(
            child: Material(
              color: on ? scheme.primary : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Haptics.segment();
                  setState(() => filter = key);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: tt.labelMedium?.copyWith(color: on ? scheme.onPrimary : scheme.onSurfaceVariant)),
                    Text('$n', style: tt.headlineMedium?.copyWith(color: on ? scheme.onPrimary : scheme.onSurface)),
                  ]),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Meetings')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => editMeeting(context, s, null),
            icon: const Icon(Icons.add),
            label: const Text('Meeting'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              Row(children: [
                tile('upcoming', 'Upcoming', upcoming.length),
                const SizedBox(width: 8),
                tile('all', 'Total', all.length),
                const SizedBox(width: 8),
                tile('done', 'Completed', done.length),
              ]),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search meetings'),
                onChanged: (v) => setState(() => query = v),
              ),
              const SizedBox(height: 8),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    all.isEmpty ? 'No meetings yet. Add one to remind you and your tenants.' : 'Nothing matches.',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final m in shown) _card(context, m, Rent.meetingDone(m, now)),
            ],
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, Rec m, bool over) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final note = ((m['desc'] as String?) ?? '').trim();
    final where = ((m['where'] as String?) ?? '').trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.groups_outlined, color: over ? scheme.onSurfaceVariant : scheme.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleMedium),
                const SizedBox(height: 6),
                statusPill(context, over ? 'Completed' : 'Upcoming', over ? scheme.onSurfaceVariant : scheme.primary),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'Meeting options',
              onSelected: (v) async {
                if (v == 'edit') await editMeeting(context, s, m);
                if (v == 'done') await s.markDone(m);
                if (v == 'delete') s.removeRec('items', m, 'Deleted meeting: ${m['title']}');
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (m['status'] != 'done') const PopupMenuItem(value: 'done', child: Text('Mark as held')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(children: [
              _row(context, 'When', niceWhen(m['when'] as int)),
              if (where.isNotEmpty) _row(context, 'Where', where),
              _row(context, 'With', _members(m)),
              if (note.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Text(note, maxLines: 3, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Adds a meeting ([m] null) or edits one. Undoable either way.
Future<void> editMeeting(BuildContext context, Store s, Rec? m) async {
  final rooms = _rooms(s);
  final title = TextEditingController(text: (m?['title'] as String?) ?? 'Meeting with tenants');
  final where = TextEditingController(text: (m?['where'] as String?) ?? '');
  final note = TextEditingController(text: (m?['desc'] as String?) ?? '');
  final picked = <int>{...((m?['rooms'] as List?) ?? const []).cast<int>()};
  final now = DateTime.now();
  var when = m == null ? DateTime(now.year, now.month, now.day + 1, 19) : DateTime.fromMillisecondsSinceEpoch(m['when'] as int);
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(m == null ? 'New meeting' : 'Edit meeting'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'About', errorText: error),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(niceWhen(when.millisecondsSinceEpoch)),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: when,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 3),
                );
                if (d == null || !ctx.mounted) return;
                final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                setD(() => when = DateTime(d.year, d.month, d.day, t?.hour ?? when.hour, t?.minute ?? when.minute));
              },
            ),
            TextField(controller: where, decoration: const InputDecoration(labelText: 'Where (like Ground floor)')),
            const SizedBox(height: 12),
            Text(picked.isEmpty ? 'With all tenants' : 'With', style: Theme.of(ctx).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final r in rooms)
                FilterChip(
                  label: Text('${r['number']}, ${r['tenant']}'),
                  selected: picked.contains(r['id']),
                  onSelected: (on) => setD(() => on ? picked.add(r['id'] as int) : picked.remove(r['id'])),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (what to discuss)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return setD(() => error = Haptics.rejected() ?? 'Say what it is about');
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final fields = <String, dynamic>{
    'meeting': true,
    'rooms': picked.toList(),
    'where': where.text.trim(),
    'desc': note.text.trim().isEmpty ? null : note.text.trim(),
  };
  if (m == null) {
    final undo = <Rec>[];
    await s.addItem(
      kind: 'event',
      title: title.text.trim(),
      when: when.millisecondsSinceEpoch,
      undo: undo,
      extra: {...fields, 'dur': 60, 'list': 'Rooms'},
    );
    s.logAction('Meeting: ${title.text.trim()}', undo);
  } else {
    final old = copyRec(m);
    m
      ..addAll(fields)
      ..['title'] = title.text.trim()
      ..['when'] = when.millisecondsSinceEpoch
      ..['status'] = when.isAfter(DateTime.now()) ? 'open' : m['status'];
    await s.syncRecord('items', m);
    s.logAction('Edited meeting: ${m['title']}', [
      {'op': 'put', 'col': 'items', 'rec': old},
    ]);
  }
  s.save();
  Haptics.tap();
}
