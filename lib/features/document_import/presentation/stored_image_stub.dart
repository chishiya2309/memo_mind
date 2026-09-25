import 'package:flutter/material.dart';

class StoredImage extends StatelessWidget {
  const StoredImage({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Icon(Icons.image_not_supported_outlined, size: 36));
}
