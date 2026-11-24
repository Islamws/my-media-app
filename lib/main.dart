import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'music_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.islamws.all_in_one.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );
  runApp(const AllInOneApp());
}

class AllInOneApp extends StatelessWidget {
  const AllInOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'All in One',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['Music', 'Video', 'Photos', 'YouTube Music'];

  Widget _soon(String name) => Center(
        child: Text(
          '$name - coming soon',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'File Manager',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File Manager - coming soon')),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          MusicPage(isActive: _index == 0),
          _soon('Video'),
          _soon('Photos'),
          _soon('YouTube Music'),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.music_note), label: 'Music'),
              NavigationDestination(icon: Icon(Icons.movie), label: 'Video'),
              NavigationDestination(icon: Icon(Icons.photo), label: 'Photos'),
              NavigationDestination(icon: Icon(Icons.play_circle), label: 'YT Music'),
            ],
          ),
        ],
      ),
    );
  }
} 
