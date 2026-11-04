import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'brain.dart';
import 'store.dart';

/// Quick capture of a typed note and/or a photo. Opened from the Jarvis bubble in Handy or from Home.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.store, this.startWithPhoto = false});
  final Store store;
  final bool startWithPhoto;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final _text = TextEditingController();
  XFile? _photo;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.startWithPhoto) WidgetsBinding.instance.addPostFrameCallback((_) => _choosePhoto());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final f = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    setState(() {
      _photo = f;
      _bytes = bytes;
    });
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty && _photo == null) return;
    final store = widget.store;
    final path = _photo?.path;
    Navigator.pop(context);
    await Brain.capture(store, t.isEmpty ? '(photo)' : t, source: path == null ? 'text' : 'photo', image: path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Tell Jarvis'),
          actions: [TextButton(onPressed: _send, child: const Text('Send'))],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _text,
              autofocus: !widget.startWithPhoto,
              minLines: 3,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type anything: a task, a plan, a thought. Add a photo of a routine, notice or list.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_photo == null)
              OutlinedButton.icon(onPressed: _choosePhoto, icon: const Icon(Icons.add_a_photo), label: const Text('Add a photo'))
            else
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_bytes!),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: IconButton.filled(onPressed: () => setState(() {
                        _photo = null;
                        _bytes = null;
                      }), icon: const Icon(Icons.close)),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _send, icon: const Icon(Icons.send), label: const Text('Send to Jarvis')),
          ],
        ),
      );
}
