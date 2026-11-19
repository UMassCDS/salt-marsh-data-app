import 'dart:convert';

// An optional extra photo on a plot; url stays null until the server has it
class AdditionalPhoto {
  AdditionalPhoto({required this.localId, required this.path, this.url});

  final String localId;
  final String path;
  String? url;

  Map<String, dynamic> toJson() => {'local_id': localId, 'path': path, 'url': url};

  factory AdditionalPhoto.fromJson(Map<String, dynamic> json) =>
      AdditionalPhoto(localId: json['local_id'] as String, path: json['path'] as String, url: json['url'] as String?);
}

String? encodeAdditionalPhotos(List<AdditionalPhoto> photos) =>
    photos.isEmpty ? null : jsonEncode([for (final p in photos) p.toJson()]);

List<AdditionalPhoto> decodeAdditionalPhotos(Object? raw) {
  if (raw is! String || raw.isEmpty) return [];
  try {
    return [for (final item in jsonDecode(raw) as List) AdditionalPhoto.fromJson(item as Map<String, dynamic>)];
  } catch (_) {
    return [];
  }
}
