import 'package:flutter/material.dart';

class PcosLogo extends StatelessWidget {
  final double size;
  const PcosLogo({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'PCOSense',
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF8A2BE2), Color(0xFFEC78AB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(Icons.spa_rounded, color: Colors.white, size: size * .6),
        ),
      );
}
