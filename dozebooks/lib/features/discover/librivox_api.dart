import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class LibriVoxBook {
  final String title;
  final List<String> authors;
  final String? zipUrl; // Can be mp3 zip or sometimes m4b link
  final String? m4bUrl;

  LibriVoxBook({
    required this.title,
    required this.authors,
    this.zipUrl,
    this.m4bUrl,
  });
}

class LibriVoxApi {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'accept': 'application/json'},
  ));

  Future<List<LibriVoxBook>> search({String title = ''}) async {
    final uri = Uri.https('librivox.org', '/api/feed/audiobooks', {
      'format': 'json',
      'title': title,
      'extended': '1',
    });
    final res = await _dio.getUri(uri);
    final data = res.data is String ? json.decode(res.data) : res.data;
    final List items = data['books'] ?? [];
    return items.map((e) {
      final urlZip = e['url_zip_file'] as String?;
      // Some projects include a top-level m4b (usually 'url_iTunes' has M4B)
      final m4b = (e['url_iTunes'] as String?)?.endsWith('.m4b') == true ? e['url_iTunes'] as String : null;
      final authors = (e['authors'] as List?)?.map((a) => a['first_name'] + ' ' + a['last_name']).cast<String>().toList() ?? [];
      return LibriVoxBook(
        title: e['title'] ?? 'Unknown',
        authors: authors,
        zipUrl: urlZip,
        m4bUrl: m4b,
      );
    }).toList();
  }

  Future<void> downloadBook(BuildContext context, LibriVoxBook book) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = book.title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '_');
    final file = File('${dir.path}/$safe.m4b');

    final url = book.m4bUrl ?? book.zipUrl;
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No direct download URL.")));
      }
      return;
    }

    try {
      final resp = await _dio.download(url, file.path, onReceiveProgress: (rcv, total) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Downloading ${book.title}: ${(rcv / (total == 0 ? 1 : total) * 100).toStringAsFixed(0)}%")));
        }
      });
      if (resp.statusCode == 200 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved to ${file.path}")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download failed: $e")));
      }
    }
  }
}
