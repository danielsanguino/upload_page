import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class UploadPage extends StatefulWidget {
  final String userId;

  const UploadPage({Key? key, required this.userId}) : super(key: key);

  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _isMergeButtonEnabled = false;
  double _mergeProgress = 0.0;
  List<String> _statusMessages = [];
  late Timer _usbCheckTimer;

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _startUsbCheckTimer();
  }

  @override
  void dispose() {
    _usbCheckTimer.cancel();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    _checkUsbStorage();
  }

  void _startUsbCheckTimer() {
    _usbCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _checkUsbStorage();
    });
  }

  Future<void> _checkUsbStorage() async {
    final directoryPath = '/mnt/media_rw/42C5-B60E';

    if (await Directory(directoryPath).exists()) {
      setState(() {
        _isMergeButtonEnabled = true;
      });
    } else {
      setState(() {
        _isMergeButtonEnabled = false;
      });
    }
  }

  Future<void> _startMerge() async {
    setState(() {
      _mergeProgress = 0.0;
      _statusMessages.clear(); // Clear previous status messages
    });

    final usbDirectoryPath = '/mnt/media_rw/42C5-B60E';
    final documentsDir = Directory('/storage/emulated/0/Documents');
    final mergedDir = Directory('${documentsDir.path}/Merged');
    final usbDirectory = Directory(usbDirectoryPath);

    if (await usbDirectory.exists()) {
      List<FileSystemEntity> files = usbDirectory.listSync();
      int totalFiles = files.where((file) => file is File && file.path.endsWith('.tsv')).length;
      int processedFiles = 0;

      for (FileSystemEntity file in files) {
        if (file is File && file.path.endsWith('.tsv')) {
          final fileName = file.uri.pathSegments.last;
          final copiedFilePath = '${documentsDir.path}/$fileName';

          try {
            // Copy the file to Documents directory
            await file.copy(copiedFilePath);
            setState(() {
              _statusMessages.add('Copied $fileName to Documents directory.');
            });

            // Convert and save to Merged directory
            await _convertTsvToCsv(File(copiedFilePath), mergedDir);
          } catch (e) {
            setState(() {
              _statusMessages.add('Error processing $fileName.');
            });
          }

          processedFiles++;
          setState(() {
            _mergeProgress = processedFiles / totalFiles;
          });
        }
      }

      // Append rows from Pico W.csv to 1721674530.csv
      await _appendRowsFromPicoWToDestination(documentsDir, mergedDir, '1721674530.csv');

      setState(() {
        _mergeProgress = 1.0;
      });
    }
  }

  Future<void> _convertTsvToCsv(File tsvFile, Directory mergedDir) async {
    final input = tsvFile.openRead();
    final fields = await input
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .map((line) => line.split('\t'))
        .toList();

    String csv = const ListToCsvConverter().convert(fields);

    String fileName = tsvFile.uri.pathSegments.last.replaceAll('.tsv', '.csv');
    File csvFile = File('${mergedDir.path}/$fileName');

    await csvFile.writeAsString(csv);

    setState(() {
      _statusMessages.add('Converted $fileName to CSV and saved in Merged directory.');
    });
  }

  Future<void> _appendRowsFromPicoWToDestination(Directory documentsDir, Directory mergedDir, String destinationFileName) async {
    final picoWFilePath = '${documentsDir.path}/Pico W.csv';
    final destinationFilePath = '${mergedDir.path}/$destinationFileName';

    try {
      final picoWRows = await _readAllRowsFromCsv(picoWFilePath);
      final destinationFile = File(destinationFilePath);
      final destinationRows = await _readAllRowsFromCsv(destinationFilePath);

      for (int i = 0; i < picoWRows.length; i++) {
        List<dynamic> row = picoWRows[i];

        if (i < destinationRows.length) {
          destinationRows[i].addAll(row);
        } else {
          List<dynamic> newRow = List<dynamic>.filled(18, '');
          newRow.addAll(row);
          destinationRows.add(newRow);
        }
      }

      final updatedCsvContent = const ListToCsvConverter().convert(destinationRows);
      await destinationFile.writeAsString(updatedCsvContent);

      setState(() {
        _statusMessages.add('Appended rows from Pico W.csv to $destinationFileName');
      });
    } catch (e) {
      setState(() {
        _statusMessages.add('Error appending rows from Pico W.csv to $destinationFileName');
      });
    }
  }

  Future<List<List<dynamic>>> _readAllRowsFromCsv(String filePath) async {
    final file = File(filePath);
    final csvContent = await file.readAsString();
    List<List<dynamic>> rows = const CsvToListConverter().convert(csvContent);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_statusMessages.isNotEmpty) ...[
              Text('Status:'),
              for (var message in _statusMessages)
                Text(message),
              SizedBox(height: 16.0),
            ],
            LinearProgressIndicator(
              value: _mergeProgress,
              minHeight: 20,
              backgroundColor: Colors.grey[300],
              color: Colors.blue,
            ),
            SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _isMergeButtonEnabled ? _startMerge : null,
              child: Text('Merge Files'),
            ),
          ],
        ),
      ),
    );
  }
}
