import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/premium/premium_service.dart';
import 'features/discover/discover_page.dart';
import 'features/library/library_page.dart';
import 'features/player/player_page.dart';
import 'features/downloads/downloads_page.dart';
import 'features/player/audio_handler_provider.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init audio handler for playback.
  final audioHandler = await initAudioHandler();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PremiumService()..load()),
        Provider.value(value: audioHandler),
      ],
      child: const DozeBooksApp(),
    ),
  );
}

class DozeBooksApp extends StatelessWidget {
  const DozeBooksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DozeBooks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int _index = 0;
  final PageStorageBucket _bucket = PageStorageBucket();

  late final List<Widget> _pages = const <Widget>[
    LibraryPage(key: PageStorageKey('library')),
    DiscoverPage(key: PageStorageKey('discover')),
    PlayerPage(key: PageStorageKey('player')),
    DownloadsPage(key: PageStorageKey('downloads')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DozeBooks')),
      body: PageStorage(
        bucket: _bucket,
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_books), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.play_circle), label: 'Player'),
          NavigationDestination(icon: Icon(Icons.download), label: 'Downloads'),
        ],
      ),
    );
  }
}
