import 'package:flutter/widgets.dart';

Widget cachedSvgAsset(String assetPath, {double? width, double? height}) {
  return Image.asset(
    assetPath,
    width: width,
    height: height,
    fit: BoxFit.contain,
  );
}
