// // lib/widgets/custom_background_container.dart
// import 'package:flutter/material.dart';
//
// class CustomBackgroundContainer extends StatelessWidget {
//   final Widget child; // This will hold the unique content of each screen
//   final String? backgroundImagePath; // Optional: for different backgrounds
//   final String? cartoonImagePath;    // Optional: for different cartoons
//
//   const CustomBackgroundContainer({
//     Key? key,
//     required this.child,
//     this.backgroundImagePath, // Default to your common background if not provided
//     this.cartoonImagePath,    // Default to your common cartoon if not provided
//   }) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     // Define default paths for your images
//     // IMPORTANT: Make sure these paths are correct in your project!
//     final String defaultBackground = 'assets/back.jpg'; // Your main purple background
//     final String defaultCartoon = 'assets/front.png';     // Your transparent cartoon image
//
//     return Stack(
//       children: [
//         // 1. Background Image (bottom layer - purple gradient)
//         Positioned.fill(
//           child: Image.asset(
//             backgroundImagePath ?? defaultBackground,
//             fit: BoxFit.cover, // Ensures the background covers the whole area
//           ),
//         ),
//
//         // 2. Cartoon Image (top layer, positioned at bottom center)
//         Align(
//           alignment: Alignment.bottomCenter, // Aligns the cartoon to the bottom center
//           child: Padding(
//             padding: const EdgeInsets.only(bottom: 20.0), // Adjust padding as needed
//             child: Image.asset(
//               cartoonImagePath ?? defaultCartoon,
//               width: 200, // Adjust width as needed for your cartoon
//               height: 200, // Adjust height as needed for your cartoon
//               // You can also use BoxFit.contain if your cartoon has specific aspect ratio needs
//             ),
//           ),
//         ),
//
//         // 3. The actual content of the screen will be rendered on top
//         child,
//       ],
//     );
//   }
// }


import 'package:flutter/material.dart';

class CustomBackgroundContainer extends StatelessWidget {
  final Widget child; // This will hold the unique content of each screen
  final String backgroundImagePath; // Path to the single combined background image

  const CustomBackgroundContainer({
    Key? key,
    required this.child,
    required this.backgroundImagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Single Background Image (covers the whole screen)
        Positioned.fill(
          child: Image.asset(
            backgroundImagePath,
            fit: BoxFit.cover, // Ensures the background covers the whole area
          ),
        ),

        // 2. The actual content of the screen will be rendered on top
        child,
      ],
    );
  }
}