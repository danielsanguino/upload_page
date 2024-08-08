import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

// Initialize logging
final _logger = Logger('UploadPage');

class UploadPage extends StatefulWidget {
  final String userId;

  const UploadPage({Key? key, required this.userId}) : super(key: key);

  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool _isUploadButtonEnabled = false;
  bool _isNextButtonEnabled = false;
  bool _isMergeButtonEnabled = false;
  double _mergeProgress = 0.0;
  double _uploadProgress = 0.0;
  String _fileContent = '';
  List<String> _statusMessages = [];
  late Timer _usbCheckTimer;

  @override
  void initState() {
    super.initState();
    _initializeLogging();
    _requestPermission();
    _checkUsbStorage();
    _startUsbCheckTimer();
  }

  @override
  void dispose() {
    _usbCheckTimer.cancel();
    super.dispose();
  }

  void _initializeLogging() {
    Logger.root.level = Level.ALL; // Set logging level
    Logger.root.onRecord.listen((record) {
      print('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  void _startUsbCheckTimer() {
    _usbCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _checkUsbStorage();
    });
  }

  Future<void> _requestPermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        _logger.warning('Storage permission denied');
        return;
      }
    }
    _logger.info('Storage permission granted');
    _checkUsbStorage();
  }

  Future<void> _checkUsbStorage() async {
    final directoryPath = '/mnt/media_rw/42C5-B60E';
    final filePath = '$directoryPath/sample.txt';

    if (await Directory(directoryPath).exists()) {
      if (await File(filePath).exists()) {
        final fileContent = await File(filePath).readAsString();
        setState(() {
          _fileContent = fileContent;
          _isMergeButtonEnabled = true;
        });
      } else {
        setState(() {
          _fileContent = 'sample.txt not found.';
        });
        _showSampleFileDialog();
      }
    } else {
      setState(() {
        _isMergeButtonEnabled = false;
      });
      _showUsbDialog();
    }
  }

  void _showUsbDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('USB Storage not detected'),
          content: Text('Please insert a USB storage device to continue.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _checkUsbStorage(); // Check again after closing the dialog
              },
              child: Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  void _showSampleFileDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('sample.txt not found'),
          content: Text(
              'Please make sure the USB storage device contains a sample.txt file.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _checkUsbStorage(); // Check again after closing the dialog
              },
              child: Text('Retry'),
            ),
          ],
        );
      },
    );
  }


  Future<void> _convertTsvToCsv(File tsvFile, Directory mergedDir) async {
    try {
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
        _statusMessages
            .add('Converted $fileName to CSV and saved in Merged directory.');
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'TSV file ${tsvFile.uri.pathSegments.last} converted to CSV and saved in Merged directory.'),
      ));
      _logger.info('Converted $fileName to CSV and saved in Merged directory.');
    } catch (e) {
      _logger.severe('Error converting TSV to CSV: $e');
    }
  }

  void _openMergedDirectory(Directory mergedDir) async {
    final mergedFilePath = '${mergedDir.path}/'; // This opens the directory, not a specific file
    final result = await OpenFile.open(mergedFilePath);
    if (result.type != ResultType.done) {
      _logger.severe('Failed to open merged directory: ${result.message}');
    } else {
      _logger.info('Merged directory opened successfully.');
    }
  }

  Future<void> _startMerge() async {
    if (!_isMergeButtonEnabled) {
      _showUsbDialog();
      return;
    }

    setState(() {
      _mergeProgress = 0.0;
      _isUploadButtonEnabled = false;
      _statusMessages.clear(); // Clear previous status messages
    });

    final usbDirectoryPath = '/mnt/media_rw/42C5-B60E';
    final documentsDir = Directory('/storage/emulated/0/Documents');
    final mergedDir = Directory('${documentsDir.path}/Merged');
    final usbDirectory = Directory(usbDirectoryPath);

    // Ensure directories exist
    if (!await documentsDir.exists()) {
      await documentsDir.create(recursive: true);
    }
    if (!await mergedDir.exists()) {
      await mergedDir.create(recursive: true);
    }

    int totalFiles = 0;
    int processedFiles = 0;

    // Process asset files
    final assetFiles = ['assets/sample1.tsv', 'assets/sample2.tsv'];
    totalFiles += assetFiles.length;

    for (String assetPath in assetFiles) {
      try {
        final byteData = await rootBundle.load(assetPath);
        final buffer = byteData.buffer;
        final tsvFile = File('${documentsDir.path}/${assetPath.split('/').last}');
        await tsvFile.writeAsBytes(buffer.asUint8List());

        setState(() {
          _statusMessages.add('Copied ${assetPath.split('/').last} to Documents directory.');
        });

        await _convertTsvToCsv(tsvFile, mergedDir);

        processedFiles++;
        setState(() {
          _mergeProgress = processedFiles / totalFiles;
        });
      } catch (e) {
        _logger.severe('Error processing $assetPath: $e');
        setState(() {
          _statusMessages.add('Error processing $assetPath.');
        });
      }
    }

    // Process USB files
    if (await usbDirectory.exists()) {
      List<FileSystemEntity> files = usbDirectory.listSync();
      totalFiles += files.where((file) => file is File && file.path.endsWith('.tsv')).length;

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

            // Handle special file with ts offsets
            if (fileName.contains('special')) {
              await _handleSpecialFileWithTs(File(copiedFilePath), mergedDir);
            } else {
              // Convert and save to Merged directory
              await _convertTsvToCsv(File(copiedFilePath), mergedDir);
            }
          } catch (e) {
            _logger.severe('Error processing $fileName: $e');
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

      // After all files are processed, handle the Pico W.csv logs
      await _processPicoWLogs(documentsDir, mergedDir);

      Timer.periodic(Duration(milliseconds: 100), (timer) {
        setState(() {
          _mergeProgress += 0.01;
          if (_mergeProgress >= 1.0) {
            _mergeProgress = 1.0;
            timer.cancel();
            _isUploadButtonEnabled = true;

            // Open the merged directory
            _openMergedDirectory(mergedDir);
          }
        });
      });
    } else {
      _showUsbDialog();
    }
  }

  Future<void> _processPicoWLogs(Directory documentsDir, Directory mergedDir) async {
    try {
      final picoWFilePath = '${documentsDir.path}/Pico W.csv';
      final picoWFile = File(picoWFilePath);

      if (await picoWFile.exists()) {
        final picoWContents = await picoWFile.readAsString();
        final picoWLogs = const CsvToListConverter().convert(picoWContents);

        for (List<dynamic> log in picoWLogs) {
          if (log.isNotEmpty && log[0] is String) {
            final humanReadableTimestamp = log[0] as String;
            final epochTimestamp = _convertToEpoch(humanReadableTimestamp);

            if (epochTimestamp != null) {
              await _addLogToFile(epochTimestamp, log, mergedDir);
            }
          }
        }
      }
    } catch (e) {
      _logger.severe('Error processing Pico W logs: $e');
    }
  }

  Future<void> _handleSpecialFileWithTs(File file, Directory mergedDir) async {
    try {
      final baseTimestamp = int.tryParse(file.uri.pathSegments.last.split('.').first);
      if (baseTimestamp == null) {
        _logger.severe('Invalid base timestamp in file name: ${file.uri.pathSegments.last}');
        return;
      }

      final csvContent = await file.readAsString();
      final csvData = const CsvToListConverter().convert(csvContent);

      for (var row in csvData) {
        if (row.isNotEmpty && row.last is String) {
          final offsetSeconds = int.tryParse(row.last.toString());
          if (offsetSeconds != null) {
            final actualTimestamp = baseTimestamp + offsetSeconds;
            await _addLogToFile(actualTimestamp, row, mergedDir);
          } else {
            _logger.warning('Invalid ts value in row: $row');
          }
        }
      }
    } catch (e) {
      _logger.severe('Error handling special file with ts offsets: $e');
    }
  }

  int? _convertToEpoch(String humanReadableTimestamp) {
    final formats = [
      DateFormat('M/d/yyyy HH:mm:ss'), // Format 1
      DateFormat('yyyy-MM-ddTHH:mm:ss'), // Format 2
      DateFormat('dd/MM/yyyy HH:mm:ss'), // Add other formats as needed
    ];

    for (var format in formats) {
      try {
        final dateTime = format.parse(humanReadableTimestamp);
        return dateTime.millisecondsSinceEpoch ~/ 1000;
      } catch (e) {
        // Continue to the next format if parsing fails
        _logger.warning('Error converting timestamp with format ${format.pattern}: $e');
      }
    }
    _logger.severe('Error converting timestamp: $humanReadableTimestamp does not match any known format.');
    return null;
  }

  Future<void> _addLogToFile(int epochTimestamp, List<dynamic> logData, Directory mergedDir) async {
    try {
      List<FileSystemEntity> mergedFiles = mergedDir.listSync();
      List<File> csvFiles = mergedFiles.whereType<File>().toList();

      csvFiles.sort((a, b) {
        final aTimestamp = int.tryParse(a.uri.pathSegments.last.split('.').first) ?? 0;
        final bTimestamp = int.tryParse(b.uri.pathSegments.last.split('.').first) ?? 0;
        return aTimestamp.compareTo(bTimestamp);
      });

      File? closestFile;
      for (File file in csvFiles) {
        final fileTimestamp = int.tryParse(file.uri.pathSegments.last.split('.').first) ?? 0;
        if (fileTimestamp > epochTimestamp) {
          closestFile = file;
          break;
        }
      }

      if (closestFile != null) {
        final csvContent = await closestFile.readAsString();
        final csvData = const CsvToListConverter().convert(csvContent);
        csvData.add(logData);

        final newCsvContent = const ListToCsvConverter().convert(csvData);
        await closestFile.writeAsString(newCsvContent);

        setState(() {
          _statusMessages.add('Added log to ${closestFile?.uri.pathSegments.last}.');
        });
        _logger.info('Added log to ${closestFile.uri.pathSegments.last}.');
      }
    } catch (e) {
      _logger.severe('Error adding log to file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upload and Merge TSV Files'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            ElevatedButton(
            onPressed: _isUploadButtonEnabled ? () {} : null,
        child: Text('Upload Data'),
      ),
      SizedBox(height: 16.0),
      ElevatedButton(
        onPressed: _isNextButtonEnabled ? () {} : null,
        child: Text('Next'),
      ),
      SizedBox(height: 16.0),
      ElevatedButton(
        onPressed: _isMergeButtonEnabled ? _startMerge : null,
        child: Text('Merge TSV to CSV'),
      ),
      SizedBox(height: 16.0),
      LinearProgressIndicator(value: _mergeProgress),
      SizedBox(height: 16.0),
      LinearProgressIndicator(value: _uploadProgress),
      SizedBox(height: 16.0),
      Text('File Content: $_fileContent'),
      SizedBox(height: 16.0),
      Text(
      'Status:',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    SizedBox(height: 8.0),
    Expanded(
    child: ListView.builder(
    itemCount: _statusMessages.length,
    itemBuilder: (context, index) {
    return ListTile(
    title: Text(_statusMessages[index]),
    );
    },
    ),
    ),
    ],
    ),
    ),
    );
  }
}










// import 'package:flutter/material.dart';
// import 'dart:async';
// import 'dart:io';
// import 'dart:convert';
// import 'package:csv/csv.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';
//
// class UploadPage extends StatefulWidget {
//   final String userId;
//
//   const UploadPage({Key? key, required this.userId}) : super(key: key);
//
//   @override
//   _UploadPageState createState() => _UploadPageState();
// }
//
// class _UploadPageState extends State<UploadPage> {
//   bool _isMergeButtonEnabled = false;
//   double _mergeProgress = 0.0;
//   List<String> _statusMessages = [];
//   late Timer _usbCheckTimer;
//
//   @override
//   void initState() {
//     super.initState();
//     _requestPermission();
//     _startUsbCheckTimer();
//   }
//
//   @override
//   void dispose() {
//     _usbCheckTimer.cancel();
//     super.dispose();
//   }
//
//   Future<void> _requestPermission() async {
//     var status = await Permission.storage.status;
//     if (!status.isGranted) {
//       status = await Permission.storage.request();
//     }
//     _checkUsbStorage();
//   }
//
//   void _startUsbCheckTimer() {
//     _usbCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
//       _checkUsbStorage();
//     });
//   }
//
//   Future<void> _checkUsbStorage() async {
//     final directoryPath = '/mnt/media_rw/42C5-B60E';
//
//     if (await Directory(directoryPath).exists()) {
//       setState(() {
//         _isMergeButtonEnabled = true;
//       });
//     } else {
//       setState(() {
//         _isMergeButtonEnabled = false;
//       });
//     }
//   }
//
//   Future<void> _startMerge() async {
//     setState(() {
//       _mergeProgress = 0.0;
//       _statusMessages.clear(); // Clear previous status messages
//     });
//
//     final usbDirectoryPath = '/mnt/media_rw/42C5-B60E';
//     final documentsDir = Directory('/storage/emulated/0/Documents');
//     final mergedDir = Directory('${documentsDir.path}/Merged');
//     final usbDirectory = Directory(usbDirectoryPath);
//
//     if (await usbDirectory.exists()) {
//       List<FileSystemEntity> files = usbDirectory.listSync();
//       int totalFiles = files.where((file) => file is File && file.path.endsWith('.tsv')).length;
//       int processedFiles = 0;
//
//       for (FileSystemEntity file in files) {
//         if (file is File && file.path.endsWith('.tsv')) {
//           final fileName = file.uri.pathSegments.last;
//           final copiedFilePath = '${documentsDir.path}/$fileName';
//
//           try {
//             // Copy the file to Documents directory
//             await file.copy(copiedFilePath);
//             setState(() {
//               _statusMessages.add('Copied $fileName to Documents directory.');
//             });
//
//             // Convert and save to Merged directory
//             await _convertTsvToCsv(File(copiedFilePath), mergedDir);
//           } catch (e) {
//             setState(() {
//               _statusMessages.add('Error processing $fileName.');
//             });
//           }
//
//           processedFiles++;
//           setState(() {
//             _mergeProgress = processedFiles / totalFiles;
//           });
//         }
//       }
//
//       // Append rows from Pico W.csv to 1721674530.csv
//       await _appendRowsFromPicoWToDestination(documentsDir, mergedDir, '1721674530.csv');
//
//       setState(() {
//         _mergeProgress = 1.0;
//       });
//     }
//   }
//
//   Future<void> _convertTsvToCsv(File tsvFile, Directory mergedDir) async {
//     final input = tsvFile.openRead();
//     final fields = await input
//         .transform(utf8.decoder)
//         .transform(LineSplitter())
//         .map((line) => line.split('\t'))
//         .toList();
//
//     String csv = const ListToCsvConverter().convert(fields);
//
//     String fileName = tsvFile.uri.pathSegments.last.replaceAll('.tsv', '.csv');
//     File csvFile = File('${mergedDir.path}/$fileName');
//
//     await csvFile.writeAsString(csv);
//
//     setState(() {
//       _statusMessages.add('Converted $fileName to CSV and saved in Merged directory.');
//     });
//   }
//
//   Future<void> _appendRowsFromPicoWToDestination(Directory documentsDir, Directory mergedDir, String destinationFileName) async {
//     final picoWFilePath = '${documentsDir.path}/Pico W.csv';
//     final destinationFilePath = '${mergedDir.path}/$destinationFileName';
//
//     try {
//       final picoWRows = await _readAllRowsFromCsv(picoWFilePath);
//       final destinationFile = File(destinationFilePath);
//       final destinationRows = await _readAllRowsFromCsv(destinationFilePath);
//
//       for (int i = 0; i < picoWRows.length; i++) {
//         List<dynamic> row = picoWRows[i];
//
//         if (i < destinationRows.length) {
//           destinationRows[i].addAll(row);
//         } else {
//           List<dynamic> newRow = List<dynamic>.filled(18, '');
//           newRow.addAll(row);
//           destinationRows.add(newRow);
//         }
//       }
//
//       final updatedCsvContent = const ListToCsvConverter().convert(destinationRows);
//       await destinationFile.writeAsString(updatedCsvContent);
//
//       setState(() {
//         _statusMessages.add('Appended rows from Pico W.csv to $destinationFileName');
//       });
//     } catch (e) {
//       setState(() {
//         _statusMessages.add('Error appending rows from Pico W.csv to $destinationFileName');
//       });
//     }
//   }
//
//   Future<List<List<dynamic>>> _readAllRowsFromCsv(String filePath) async {
//     final file = File(filePath);
//     final csvContent = await file.readAsString();
//     List<List<dynamic>> rows = const CsvToListConverter().convert(csvContent);
//     return rows;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Upload Data'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             if (_statusMessages.isNotEmpty) ...[
//               Text('Status:'),
//               for (var message in _statusMessages)
//                 Text(message),
//               SizedBox(height: 16.0),
//             ],
//             LinearProgressIndicator(
//               value: _mergeProgress,
//               minHeight: 20,
//               backgroundColor: Colors.grey[300],
//               color: Colors.blue,
//             ),
//             SizedBox(height: 16.0),
//             ElevatedButton(
//               onPressed: _isMergeButtonEnabled ? _startMerge : null,
//               child: Text('Merge Files'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
