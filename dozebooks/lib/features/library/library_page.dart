import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:audio_service/audio_service.dart';
import '../player/audio_handler_provider.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final List<File> _books = [];

  Future<void> _addBook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4b'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _books.add(File(result.files.single.path!));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<AudioHandler>(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _addBook,
                icon: const Icon(Icons.add),
                label: const Text("Add M4B"),
              ),
              const SizedBox(width: 12),
              Text("${_books.length} books"),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _books.length,
            itemBuilder: (context, i) {
              final f = _books[i];
              return ListTile(
                leading: const Icon(Icons.audiotrack),
                title: Text(f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : f.path),
                subtitle: Text(f.path),
                onTap: () {
                  audioHandler.customAction('playUri', {'uri': f.uri.toString()});
                },
                trailing: IconButton(
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => audioHandler.customAction('playUri', {'uri': f.uri.toString()}),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
