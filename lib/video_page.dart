import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'library.dart' show baseName, titleOf;
import 'video_player_page.dart';

const _videoExts = {
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp',
  '.flv', '.ts', '.m4v', '.wmv', '.mpg', '.mpeg',
};

bool _isVideo(String path) {
  final i = path.lastIndexOf('.');
  return i != -1 && _videoExts.contains(path.substring(i).toLowerCase());
}

String _dirOf(String path) => path.substring(0, path.lastIndexOf('/'));

String fmtSize(int bytes) {
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}

class VideoFile {
  final String path;
  final int size;
  final int modified;
  const VideoFile(this.path, this.size, this.modified);
}

class VideoLibrary extends ChangeNotifier {
  List<VideoFile> files = [];
  bool scanning = false;

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    final out = <VideoFile>[];
    await _walk(Directory('/storage/emulated/0'), out);
    files = out;
    scanning = false;
    notifyListeners();
  }

  Future<void> _walk(Directory dir, List<VideoFile> out) async {
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = baseName(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          if (e.path == '/storage/emulated/0/Android') continue;
          await _walk(e, out);
        } else if (e is File && _isVideo(e.path)) {
          try {
            final s = await e.stat();
            out.add(VideoFile(e.path, s.size, s.modified.millisecondsSinceEpoch));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

final VideoLibrary videoLibrary = VideoLibrary();

class VideoPage extends StatefulWidget {
  final bool isActive;
  const VideoPage({super.key, required this.isActive});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  bool granted = false;
  String? openFolder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _maybeScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !granted) _check();
  }

  Future<void> _check() async {
    final ok = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() => granted = ok);
    _maybeScan();
  }

  void _maybeScan() {
    if (granted &&
        widget.isActive &&
        videoLibrary.files.isEmpty &&
        !videoLibrary.scanning) {
      videoLibrary.scan();
    }
  }

  Future<void> _ask() async {
    await Permission.manageExternalStorage.request();
    _check();
  }

  Widget _folders(Map<String, List<VideoFile>> groups) {
    final dirs = groups.keys.toList()
      ..sort((a, b) =>
          baseName(a).toLowerCase().compareTo(baseName(b).toLowerCase()));
    if (dirs.isEmpty) return const Center(child: Text('No videos found'));
    return ListView.builder(
      itemCount: dirs.length,
      itemBuilder: (context, i) {
        final d = dirs[i];
        return ListTile(
          leading: Icon(Icons.folder,
              size: 36, color: Theme.of(context).colorScheme.primary),
          title: Text(baseName(d)),
          subtitle: Text(
            '${groups[d]!.length} videos • $d',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => setState(() => openFolder = d),
        );
      },
    );
  }

  Widget _files(List<VideoFile> list) {
    final sorted = [...list]..sort((a, b) =>
        baseName(a.path).toLowerCase().compareTo(baseName(b.path).toLowerCase()));
    final paths = [for (final f in sorted) f.path];
    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, i) {
        final f = sorted[i];
        final ext = f.path.substring(f.path.lastIndexOf('.') + 1).toUpperCase();
        return ListTile(
          leading: Container(
            width: 64,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.play_arrow),
          ),
          title: Text(titleOf(f.path), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${fmtSize(f.size)} • $ext'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoPlayerPage(paths: paths, index: i),
            ),
          ),
        );
      },
    );
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
              const Icon(Icons.movie, size: 64),
              const SizedBox(height: 16),
              const Text(
                'To find your videos, allow access to all files.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _ask, child: const Text('Grant access')),
            ],
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: videoLibrary,
      builder: (context, _) {
        final groups = <String, List<VideoFile>>{};
        for (final f in videoLibrary.files) {
          groups.putIfAbsent(_dirOf(f.path), () => []).add(f);
        }
        final inFolder = openFolder != null;
        return PopScope(
          canPop: !inFolder || !widget.isActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(() => openFolder = null);
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    if (inFolder)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => setState(() => openFolder = null),
                      ),
                    Expanded(
                      child: Text(
                        inFolder ? baseName(openFolder!) : 'Folders',
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Rescan',
                      onPressed: videoLibrary.scan,
                    ),
                  ],
                ),
              ),
              if (videoLibrary.scanning) const LinearProgressIndicator(),
              Expanded(
                child: inFolder
                    ? _files(groups[openFolder] ?? [])
                    : _folders(groups),
              ),
            ],
          ),
        );
      },
    );
  }
}
