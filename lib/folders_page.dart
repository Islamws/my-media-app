import 'dart:io';
import 'package:flutter/material.dart';
import 'library.dart';

class FolderBrowser extends StatefulWidget {
  final bool active;
  const FolderBrowser({super.key, required this.active});

  @override
  State<FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<FolderBrowser>
    with AutomaticKeepAliveClientMixin {
  static const root = '/storage/emulated/0';
  Directory current = Directory(root);
  List<FileSystemEntity> items = [];
  String? error;

  bool get atRoot => current.path == root;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await current.list().toList();
      final visible =
          list.where((e) => !baseName(e.path).startsWith('.')).toList();
      visible.sort((a, b) {
        final ad = a is Directory;
        final bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return baseName(a.path)
            .toLowerCase()
            .compareTo(baseName(b.path).toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        items = visible;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        items = [];
        error = 'Cannot open this folder';
      });
    }
  }

  void _open(Directory d) {
    setState(() => current = d);
    _load();
  }

  void _up() {
    setState(() => current = current.parent);
    _load();
  }

  Future<void> _play(File f) async {
    final files =
        items.whereType<File>().where((x) => isAudio(x.path)).toList();
    final idx = files.indexWhere((x) => x.path == f.path);
    try {
      await playQueue(
        [for (final x in files) musicLibrary.trackFor(x.path)],
        idx,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cannot play: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: atRoot || !widget.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Text(
              current.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: error != null
                ? Center(child: Text(error!))
                : items.isEmpty
                    ? const Center(child: Text('Empty folder'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          final name = baseName(e.path);
                          if (e is Directory) {
                            return ListTile(
                              leading: const Icon(Icons.folder),
                              title: Text(name),
                              onTap: () => _open(e),
                            );
                          }
                          final audio = isAudio(e.path);
                          return ListTile(
                            leading: Icon(
                              audio ? Icons.music_note : Icons.insert_drive_file,
                            ),
                            title: Text(name),
                            enabled: audio,
                            onTap: audio ? () => _play(e as File) : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
