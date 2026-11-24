import 'dart:convert';
import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' as meta;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

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

String fmtDuration(int ms) {
  if (ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class Track {
  final String path;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int size;
  final int modified;
  final String? cover;

  const Track({
    required this.path,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
    this.size = 0,
    this.modified = 0,
    this.cover,
  });

  Map<String, dynamic> toJson() => {
        'p': path,
        't': title,
        'ar': artist,
        'al': album,
        'd': durationMs,
        's': size,
        'm': modified,
        'c': cover,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        path: j['p'] as String,
        title: j['t'] as String,
        artist: (j['ar'] ?? '') as String,
        album: (j['al'] ?? '') as String,
        durationMs: (j['d'] ?? 0) as int,
        size: (j['s'] ?? 0) as int,
        modified: (j['m'] ?? 0) as int,
        cover: j['c'] as String?,
      );

  MediaItem toMediaItem() => MediaItem(
        id: path,
        title: title,
        artist: artist.isEmpty ? null : artist,
        album: album.isEmpty ? null : album,
        duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
        artUri: cover != null ? Uri.file(cover!) : null,
      );
}

class MusicLibrary extends ChangeNotifier {
  List<Track> tracks = [];
  Map<String, Track> _byPath = {};
  bool scanning = false;
  int total = 0;
  final ValueNotifier<int> scanned = ValueNotifier<int>(0);

  bool _loaded = false;
  late Directory _dir;

  Track trackFor(String path) =>
      _byPath[path] ?? Track(path: path, title: titleOf(path));

  Future<void> load() async {
    if (_loaded) return;
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/library');
    Directory('${_dir.path}/covers').createSync(recursive: true);
    final f = File('${_dir.path}/tracks.json');
    if (await f.exists()) {
      try {
        final list = jsonDecode(await f.readAsString()) as List;
        tracks = list
            .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _byPath = {for (final t in tracks) t.path: t};
      } catch (_) {}
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> scan() async {
    if (scanning) return;
    if (!_loaded) await load();
    scanning = true;
    total = 0;
    scanned.value = 0;
    notifyListeners();

    final paths = <String>[];
    await _walk(Directory('/storage/emulated/0'), paths);
    total = paths.length;

    final result = <Track>[];
    var n = 0;
    for (final p in paths) {
      n++;
      try {
        final file = File(p);
        final stat = await file.stat();
        if (stat.size < 200 * 1024) continue;
        final mod = stat.modified.millisecondsSinceEpoch;
        final old = _byPath[p];
        if (old != null && old.size == stat.size && old.modified == mod) {
          result.add(old);
        } else {
          result.add(_readTrack(file, stat.size, mod));
        }
      } catch (_) {}
      if (n % 10 == 0) {
        scanned.value = n;
        await Future.delayed(Duration.zero);
      }
    }
    scanned.value = n;

    tracks = result;
    _byPath = {for (final t in tracks) t.path: t};
    try {
      await File('${_dir.path}/tracks.json').writeAsString(
        jsonEncode(tracks.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
    scanning = false;
    notifyListeners();
  }

  Future<void> _walk(Directory dir, List<String> out) async {
    try {
      await for (final e in dir.list(followLinks: false)) {
        final name = baseName(e.path);
        if (name.startsWith('.')) continue;
        if (e is Directory) {
          if (e.path == '/storage/emulated/0/Android') continue;
          if (name.toLowerCase().contains('whatsapp')) continue;
          await _walk(e, out);
        } else if (e is File && isAudio(e.path)) {
          out.add(e.path);
        }
      }
    } catch (_) {}
  }

  Track _readTrack(File file, int size, int modified) {
    var title = titleOf(file.path);
    var artist = '';
    var album = '';
    var dur = 0;
    String? cover;
    try {
      final m = meta.readMetadata(file, getImage: true);
      final t = m.title?.trim() ?? '';
      if (t.isNotEmpty) title = t;
      artist = m.artist?.trim() ?? '';
      album = m.album?.trim() ?? '';
      dur = m.duration?.inMilliseconds ?? 0;
      if (m.pictures.isNotEmpty) {
        final seed = album.isNotEmpty ? '$artist|$album' : file.path;
        final key = seed.hashCode.toUnsigned(32).toRadixString(16);
        final cf = File('${_dir.path}/covers/$key.jpg');
        if (!cf.existsSync()) cf.writeAsBytesSync(m.pictures.first.bytes);
        cover = cf.path;
      }
    } catch (_) {}
    return Track(
      path: file.path,
      title: title,
      artist: artist,
      album: album,
      durationMs: dur,
      size: size,
      modified: modified,
      cover: cover,
    );
  }
}

final MusicLibrary musicLibrary = MusicLibrary();

Future<void> playQueue(List<Track> list, int index) async {
  final source = ConcatenatingAudioSource(children: [
    for (final t in list) AudioSource.file(t.path, tag: t.toMediaItem()),
  ]);
  await player.setAudioSource(source, initialIndex: index);
  player.play();
}

class Cover extends StatelessWidget {
  final String? path;
  final double size;
  final double radius;
  const Cover({super.key, this.path, this.size = 48, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note,
          size: size * 0.5, color: scheme.onSurfaceVariant),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: path == null
          ? placeholder
          : Image.file(
              File(path!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
