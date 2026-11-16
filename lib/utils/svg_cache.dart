import 'package:flutter_svg/flutter_svg.dart';

final Map<String, SvgPicture> _svgCache = {};

SvgPicture cachedSvgAsset(String assetPath, {double? width, double? height}) {
  final key = '$assetPath|$width|$height';
  return _svgCache.putIfAbsent(
    key,
    () => SvgPicture.asset(assetPath, width: width, height: height),
  );
}
