import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'library.dart' show player, baseName, titleOf;

String _fmt(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

class _Opt {
  final String id;
  final String label;
  final VoidCallback onPick;
  const _Opt(this.id, this.label, this.onPick);
}

class VideoPlayerPage extends StatefulWidget {
  final List<String> paths;
  final int index;
  const VideoPlayerPage({super.key, required this.paths, required this.index});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final mk.Player _vp = mk.Player();
    late final VideoController _controller;
  String? _error;
  final List<StreamSubscription> _subs = [];

  int _index = 0;
  bool _showControls = true;
  bool _locked = false;
  bool _landscape = true;
  BoxFit _fit = BoxFit.contain;
  double _volume = 100;
  Timer? _hideTimer;
  Timer? _toastTimer;
  String? _toast;

  double _tapX = 0;
  Duration _dragBase = Duration.zero;
  double _dragDx = 0;
  Duration? _dragTarget;
  bool _vertRight = false;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
        _controller = VideoController(_vp);
    player.pause(); // stop the music player
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _subs.add(_vp.stream.playlist.listen((p) {
      if (mounted && p.index != _index) setState(() => _index = p.index);
    }));
    _subs.add(_vp.stream.error.listen((e) {
      if (mounted) _flash('Error: $e');
    }));
    _vp.open(mk.Playlist(
      [for (final p in widget.paths) mk.Media(p)],
      index: widget.index,
    ));
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _toastTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _vp.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _flash(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _seekBy(int seconds) {
    var t = _vp.state.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    final d = _vp.state.duration;
    if (d > Duration.zero && t > d) t = d;
    _vp.seek(t);
    _flash(seconds > 0 ? '+${seconds}s' : '${seconds}s');
  }

  void _cycleFit() {
    setState(() {
      if (_fit == BoxFit.contain) {
        _fit = BoxFit.cover;
        _flash('Fill');
      } else if (_fit == BoxFit.cover) {
        _fit = BoxFit.fill;
        _flash('Stretch');
      } else {
        _fit = BoxFit.contain;
        _flash('Fit');
      }
    });
  }

  void _rotate() {
    _landscape = !_landscape;
    SystemChrome.setPreferredOrientations(_landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
  }

  String _label(String id, String? title, String? lang) {
    if (id == 'auto') return 'Auto';
    if (id == 'no') return 'Off';
    final parts = [lang, title].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? 'Track $id' : parts.join(' - ');
  }

  void _openSheet(String title, List<_Opt> opts, String? currentId) {
    _hideTimer?.cancel();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final o in opts)
              ListTile(
                title: Text(o.label),
                trailing: o.id == currentId ? const Icon(Icons.check) : null,
                onTap: () {
                  o.onPick();
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    ).whenComplete(_scheduleHide);
  }

  void _pickAudio() {
    _openSheet(
      'Audio track',
      [
        for (final t in _vp.state.tracks.audio)
          _Opt(t.id, _label(t.id, t.title, t.language),
              () => _vp.setAudioTrack(t)),
      ],
      _vp.state.track.audio.id,
    );
  }

  void _pickSubtitle() {
    _openSheet(
      'Subtitles',
      [
        for (final t in _vp.state.tracks.subtitle)
          _Opt(t.id, _label(t.id, t.title, t.language),
              () => _vp.setSubtitleTrack(t)),
      ],
      _vp.state.track.subtitle.id,
    );
  }

  void _pickSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    _openSheet(
      'Speed',
      [
        for (final s in speeds)
          _Opt('$s', '${s}x', () => _vp.setRate(s)),
      ],
      '${_vp.state.rate}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          return Stack(
            children: [
              Positioned.fill(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: _fit,
                ),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
                  onDoubleTap: _locked
                      ? null
                      : () {
                          if (_tapX < w / 3) {
                            _seekBy(-10);
                          } else if (_tapX > 2 * w / 3) {
                            _seekBy(10);
                          } else {
                            _vp.playOrPause();
                          }
                        },
                  onHorizontalDragStart: _locked
                      ? null
                      : (_) {
                          _dragBase = _vp.state.position;
                          _dragDx = 0;
                          _dragTarget = _dragBase;
                        },
                  onHorizontalDragUpdate: _locked
                      ? null
                      : (d) {
                          final dur = _vp.state.duration;
                          if (dur <= Duration.zero) return;
                          _dragDx += d.delta.dx;
                          var t = _dragBase +
                              Duration(seconds: (_dragDx / w * 120).round());
                          if (t < Duration.zero) t = Duration.zero;
                          if (t > dur) t = dur;
                          setState(() => _dragTarget = t);
                        },
                  onHorizontalDragEnd: _locked
                      ? null
                      : (_) {
                          final t = _dragTarget;
                          if (t != null) _vp.seek(t);
                          setState(() => _dragTarget = null);
                        },
                  onVerticalDragStart: _locked
                      ? null
                      : (d) => _vertRight = d.localPosition.dx > w / 2,
                  onVerticalDragUpdate: _locked
                      ? null
                      : (d) {
                          if (!_vertRight) return;
                          _volume = (_volume - d.delta.dy / h * 120)
                              .clamp(0.0, 100.0)
                              .toDouble();
                          _vp.setVolume(_volume);
                          _flash('Volume ${_volume.round()}%');
                        },
                ),
              ),
              if (_dragTarget != null || _toast != null)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _dragTarget != null ? _fmt(_dragTarget!) : _toast!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 28),
                      ),
                    ),
                  ),
                ),
              if (_showControls)
                _locked ? _lockOverlay() : _controlsOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _lockOverlay() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: IconButton.filledTonal(
          icon: const Icon(Icons.lock),
          onPressed: () {
            setState(() => _locked = false);
            _scheduleHide();
          },
        ),
      ),
    );
  }

  Widget _controlsOverlay() {
    const white = Colors.white;
    final title = baseName(widget.paths[_index.clamp(0, widget.paths.length - 1)]);
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    titleOf(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: white, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.subtitles, color: white),
                  onPressed: _pickSubtitle,
                ),
                IconButton(
                  icon: const Icon(Icons.audiotrack, color: white),
                  onPressed: _pickAudio,
                ),
                IconButton(
                  icon: const Icon(Icons.speed, color: white),
                  onPressed: _pickSpeed,
                ),
                IconButton(
                  icon: const Icon(Icons.aspect_ratio, color: white),
                  onPressed: _cycleFit,
                ),
                IconButton(
                  icon: const Icon(Icons.screen_rotation, color: white),
                  onPressed: _rotate,
                ),
                IconButton(
                  icon: const Icon(Icons.lock_open, color: white),
                  onPressed: () => setState(() {
                    _locked = true;
                    _showControls = true;
                    _scheduleHide();
                  }),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<Duration>(
                  stream: _vp.stream.duration,
                  initialData: _vp.state.duration,
                  builder: (context, ds) {
                    final dur = ds.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: _vp.stream.position,
                      initialData: _vp.state.position,
                      builder: (context, ps) {
                        final pos = ps.data ?? Duration.zero;
                        final maxMs =
                            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                        final value = pos.inMilliseconds
                            .toDouble()
                            .clamp(0.0, maxMs)
                            .toDouble();
                        return Row(
                          children: [
                            Text(_fmt(pos), style: const TextStyle(color: white)),
                            Expanded(
                              child: Slider(
                                value: value,
                                max: maxMs,
                                onChanged: dur.inMilliseconds > 0
                                    ? (v) {
                                        _scheduleHide();
                                        _vp.seek(Duration(milliseconds: v.round()));
                                      }
                                    : null,
                              ),
                            ),
                            Text(_fmt(dur), style: const TextStyle(color: white)),
                          ],
                        );
                      },
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.skip_previous, color: white),
                      onPressed: _vp.previous,
                    ),
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.replay_10, color: white),
                      onPressed: () => _seekBy(-10),
                    ),
                    StreamBuilder<bool>(
                      stream: _vp.stream.playing,
                      initialData: _vp.state.playing,
                      builder: (context, s) => IconButton(
                        iconSize: 48,
                        icon: Icon(
                          (s.data ?? false) ? Icons.pause_circle : Icons.play_circle,
                          color: white,
                        ),
                        onPressed: _vp.playOrPause,
                      ),
                    ),
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.forward_10, color: white),
                      onPressed: () => _seekBy(10),
                    ),
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.skip_next, color: white),
                      onPressed: _vp.next,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
