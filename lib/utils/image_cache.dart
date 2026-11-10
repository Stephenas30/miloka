import 'package:flutter/painting.dart';

final Map<String, NetworkImage> _networkImageCache = {};

NetworkImage cachedNetworkImage(String url) {
  return _networkImageCache.putIfAbsent(url, () => NetworkImage(url));
}