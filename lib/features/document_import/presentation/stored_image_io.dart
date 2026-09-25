import 'dart:io';

import 'package:flutter/material.dart';

class StoredImage extends StatelessWidget {
  const StoredImage({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.file(
    File(path),
    fit: fit,
    errorBuilder: (context, error, stackTrace) =>
        const Center(child: Icon(Icons.broken_image_outlined, size: 36)),
  );
}
