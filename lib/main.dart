import 'package:flutter/material.dart';
import 'upload_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: UploadPage(
        userId: '12345'), // Pass a sample userId
    );
  }
}
