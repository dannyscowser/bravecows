import 'package:flutter/material.dart';

class CowLoader extends StatefulWidget {
  final double size;
  const CowLoader({super.key, this.size = 72});

  @override
  State<CowLoader> createState() => _CowLoaderState();
}

class _CowLoaderState extends State<CowLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _tilt;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _tilt = Tween(begin: -0.08, end: 0.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _tilt,
      child: Image.asset(
        'assets/cows_dayin.png',
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}
