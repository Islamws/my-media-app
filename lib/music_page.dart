import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

final AudioPlayer player = AudioPlayer();

const _audioExts = {'.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma'};

bool isAudio(String path) {
  final i = path.lastIndexOf('.');
  return i != -1 && _audioExts.contains(path.substring(i).toLowerCase());
}

String baseName(String path) {
  final parts = path.split('/').where((e) => e.isNotEmpty).toList();
  return parts.isEmpty ? '' : parts.last;
}

String titleOf(String path) {
  final name = baseName(path);
  final i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}

class MusicPage extends StatefulWidget {
  final bool isActive;
  const MusicPage({super.key, required this.isActive});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> with WidgetsBindingObserver {
  static const root = '/storage/emulated/0';
  Directory current = Directory(root);
  List<FileSystemEntity> items = [];
  bool granted = false;
  String? error;

  bool get atRoot => current.path == root;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !granted) _checkAccess();
  }

  Future<void> _init() async {
    await Permission.notification.request();
    await _checkAccess();
  }

  Future<void> _checkAccess() async {
    final ok = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() => granted = ok);
    if (ok) _load();
  }

  Future<void> _askAccess() async {
    await Permission.manageExternalStorage.request();
    _checkAccess();
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
    final files = items
        .whereType<File>()
        .where((x) => isAudio(x.path))
        .toList();
    final idx = files.indexWhere((x) => x.path == f.path);
    final source = ConcatenatingAudioSource(children: [
      for (final x in files)
        AudioSource.file(
          x.path,
          tag: MediaItem(id: x.path, title: titleOf(x.path)),
        ),
    ]);
    try {
      await player.setAudioSource(source, initialIndex: idx);
      player.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cannot play: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!granted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_open, size: 64),
              const SizedBox(height: 16),
              const Text(
                'To browse your files, allow access to all files.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _askAccess,
                child: const Text('Grant access'),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: atRoot || !widget.isActive,
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

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snap) {
        final tag = snap.data?.currentSource?.tag;
        if (tag is! MediaItem) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, ps) {
                  final total = player.duration?.inMilliseconds ?? 0;
                  final pos = ps.data?.inMilliseconds ?? 0;
                  return LinearProgressIndicator(
                    value: total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0,
                    minHeight: 2,
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.music_note),
                title: Text(
                  tag.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      onPressed: player.seekToPrevious,
                    ),
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      builder: (context, st) {
                        final playing = st.data?.playing ?? false;
                        return IconButton(
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          onPressed: playing ? player.pause : player.play,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      onPressed: player.seekToNext,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
