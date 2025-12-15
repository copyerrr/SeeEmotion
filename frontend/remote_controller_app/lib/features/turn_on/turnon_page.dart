import 'dart:async';
import 'package:flutter/material.dart';
import '../home/home_page.dart';

class TurnOnPage extends StatefulWidget {
  const TurnOnPage({super.key});

  @override
  State<TurnOnPage> createState() => _TurnOnPageState();
}

class _TurnOnPageState extends State<TurnOnPage> {
  @override
  void initState() {
    super.initState();
    // 3초 후 자동으로 홈 화면으로 이동
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const HomePage(),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Image.asset(
          'assets/배경화면.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

