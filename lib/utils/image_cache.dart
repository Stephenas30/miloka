import 'package:flutter/painting.dart';

const int _maxCacheEntries = 40;

final Map<String, NetworkImage> _networkImageCache = {};

NetworkImage cachedNetworkImage(String url) => _cache(url);

NetworkImage _cache(String url) {
  final cached = _networkImageCache.remove(url);
  if (cached != null) {
    _networkImageCache[url] = cached;
    return cached;
  }
  final image = NetworkImage(url);
  if (_networkImageCache.length >= _maxCacheEntries) {
    _networkImageCache.remove(_networkImageCache.keys.first);
  }
  _networkImageCache[url] = image;
  return image;
}
