import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'library.dart';

String _fmt(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Now playing'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(),
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.music_note, size: 120, color: scheme.primary),
              ),
            ),
            const SizedBox(height: 32),
            StreamBuilder<SequenceState?>(
              stream: player.sequenceStateStream,
              builder: (context, snap) {
                final tag = snap.data?.currentSource?.tag;
                final title = tag is MediaItem ? tag.title : '';
                return Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                );
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, ps) {
                final total = player.duration ?? Duration.zero;
                final pos = ps.data ?? Duration.zero;
                final maxMs = total.inMilliseconds > 0
                    ? total.inMilliseconds.toDouble()
                    : 1.0;
                final value =
                    pos.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();
                return Column(
                  children: [
                    Slider(
                      value: value,
                      max: maxMs,
                      onChanged: total.inMilliseconds > 0
                          ? (v) => player.seek(Duration(milliseconds: v.round()))
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(_fmt(pos)), Text(_fmt(total))],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                StreamBuilder<bool>(
                  stream: player.shuffleModeEnabledStream,
                  builder: (context, s) {
                    final on = s.data ?? false;
                    return IconButton(
                      icon: Icon(Icons.shuffle,
                          color: on ? scheme.primary : null),
                      onPressed: () async {
                        if (!on) await player.shuffle();
                        await player.setShuffleModeEnabled(!on);
                      },
                    );
                  },
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: player.seekToPrevious,
                ),
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, st) {
                    final playing = st.data?.playing ?? false;
                    return IconButton.filled(
                      iconSize: 48,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: playing ? player.pause : player.play,
                    );
                  },
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next),
                  onPressed: player.seekToNext,
                ),
                StreamBuilder<LoopMode>(
                  stream: player.loopModeStream,
                  builder: (context, s) {
                    final mode = s.data ?? LoopMode.off;
                    return IconButton(
                      icon: Icon(
                        mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                        color: mode == LoopMode.off ? null : scheme.primary,
                      ),
                      onPressed: () => player.setLoopMode(
                        mode == LoopMode.off
                            ? LoopMode.all
                            : mode == LoopMode.all
                                ? LoopMode.one
                                : LoopMode.off,
                      ),
                    );
                  },
                ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
