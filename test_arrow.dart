import 'package:flutter/material.dart';

void main() {
  runApp(const TestArrowApp());
}

class TestArrowApp extends StatelessWidget {
  const TestArrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Arrow at 0° rotation (no transform)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              // Draw coordinate axes
              Stack(
                alignment: Alignment.center,
                children: [
                  // Horizontal axis (blue)
                  Container(
                    width: 400,
                    height: 2,
                    color: Colors.blue,
                  ),
                  // Vertical axis (green)
                  Container(
                    width: 2,
                    height: 400,
                    color: Colors.green,
                  ),
                  // Arrow at 0° rotation (natural orientation from PNG)
                  Image.asset(
                    'assets/images/arrow.png',
                    width: 200,
                    height: 200 * 0.2, // Maintain aspect ratio
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'This shows the arrow\'s natural orientation in the PNG file',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

