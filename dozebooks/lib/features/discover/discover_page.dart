import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/premium/premium_service.dart';
import 'librivox_api.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _api = LibriVoxApi();
  List<LibriVoxBook> _books = [];
  bool _loading = false;
  // BannerAd? _banner;

  @override
  void initState() {
    super.initState();
    _search("");
    final isPremium = context.read<PremiumService>().isPremium;
    // if (!isPremium) {
    //   _banner = BannerAd(
    //     adUnitId: 'ca-app-pub-3940256099942544/6300978111', // test ad unit
    //     size: AdSize.banner,
    //     request: const AdRequest(),
    //     listener: BannerAdListener(),
    //   )..load();
    // }
  }

  @override
  void dispose() {
    // _banner?.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final res = await _api.search(title: q);
    setState(() {
      _books = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumService>().isPremium;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: "Search LibriVox"),
            onSubmitted: _search,
          ),
        ),
        // if (!isPremium && _banner != null) SizedBox(
        //   height: _banner!.size.height.toDouble(),
        //   width: _banner!.size.width.toDouble(),
        //   child: AdWidget(ad: _banner!),
        // ),
        const Divider(height: 1),
        Expanded(
          child: _loading ? const Center(child: CircularProgressIndicator()) :
          ListView.builder(
            itemCount: _books.length,
            itemBuilder: (context, i) {
              final b = _books[i];
              return ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(b.title),
                subtitle: Text(b.authors.join(", ")),
                trailing: FilledButton(
                  onPressed: () => _api.downloadBook(context, b),
                  child: const Text("Download"),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
