import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'folders_page.dart';
import 'library.dart';
import 'now_playing_page.dart';

enum SortMode { title, artist, newest, longest }

class MusicPage extends StatefulWidget {
  final bool isActive;
  const MusicPage({super.key, required this.isActive});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool granted = false;
  String query = '';
  SortMode sort = SortMode.title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !granted) _checkAccess();
  }

  Future<void> _init() async {
    await musicLibrary.load();
    await Permission.notification.request();
    await _checkAccess();
  }

  Future<void> _checkAccess() async {
    final ok = await Permission.manageExternalStorage.isGranted;
    if (!mounted) return;
    setState(() => granted = ok);
    if (ok) musicLibrary.scan();
  }

  Future<void> _askAccess() async {
    await Permission.manageExternalStorage.request();
    _checkAccess();
  }

  int _compare(Track a, Track b) {
    switch (sort) {
      case SortMode.title:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case SortMode.artist:
        final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        return c != 0
            ? c
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case SortMode.newest:
        return b.modified.compareTo(a.modified);
      case SortMode.longest:
        return b.durationMs.compareTo(a.durationMs);
    }
  }

  Widget _songs() {
    return ListenableBuilder(
      listenable: musicLibrary,
      builder: (context, _) {
        final list = musicLibrary.tracks
            .where((t) =>
                query.isEmpty ||
                t.title.toLowerCase().contains(query) ||
                t.artist.toLowerCase().contains(query) ||
                t.album.toLowerCase().contains(query))
            .toList();
        list.sort(_compare);
        if (list.isEmpty) {
          return Center(
            child: Text(
              musicLibrary.scanning
                  ? 'Scanning...'
                  : musicLibrary.tracks.isEmpty
                      ? 'No songs found'
                      : 'No results',
            ),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemExtent: 64,
          itemBuilder: (context, i) {
            final t = list[i];
            final sub = [t.artist, t.album].where((s) => s.isNotEmpty).join(' • ');
            return ListTile(
              dense: true,
              leading: Cover(path: t.cover),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                sub.isEmpty ? baseName(t.path) : sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                fmtDuration(t.durationMs),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () => playQueue(list, i),
            );
          },
        );
      },
    );
  }

  Widget _scanBanner() {
    return ListenableBuilder(
      listenable: musicLibrary,
      builder: (context, _) {
        if (!musicLibrary.scanning) return const SizedBox.shrink();
        return ValueListenableBuilder<int>(
          valueListenable: musicLibrary.scanned,
          builder: (context, n, _) {
            final total = musicLibrary.total;
            return Column(
              children: [
                LinearProgressIndicator(value: total > 0 ? n / total : null),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    total > 0 ? 'Scanning $n / $total' : 'Looking for songs...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
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
              const Icon(Icons.folder_open, size: 64),
              const SizedBox(height: 16),
              const Text(
                'To find your music, allow access to all files.',
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) =>
                      setState(() => query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search songs',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<SortMode>(
                icon: const Icon(Icons.sort),
                tooltip: 'Sort',
                onSelected: (m) => setState(() => sort = m),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: SortMode.title, child: Text('Title')),
                  PopupMenuItem(value: SortMode.artist, child: Text('Artist')),
                  PopupMenuItem(value: SortMode.newest, child: Text('Newest')),
                  PopupMenuItem(value: SortMode.longest, child: Text('Longest')),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Rescan',
                onPressed: musicLibrary.scan,
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Songs'), Tab(text: 'Folders')],
        ),
        _scanBanner(),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _songs(),
              FolderBrowser(active: widget.isActive && _tabs.index == 1),
            ],
          ),
        ),
      ],
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NowPlayingPage(),
                    fullscreenDialog: true,
                  ),
                ),
                leading: Cover(path: tag.artUri?.toFilePath(), size: 40),
                title: Text(
                  tag.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: tag.artist == null
                    ? null
                    : Text(
                        tag.artist!,
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
