/// Modelo de una foto de vinilo subida por el usuario
class AlbumPhotoModel {
  final String id;
  final String albumId;
  final String userId;
  final String photoUrl;
  final String? caption;
  final DateTime createdAt;

  const AlbumPhotoModel({
    required this.id,
    required this.albumId,
    required this.userId,
    required this.photoUrl,
    this.caption,
    required this.createdAt,
  });

  factory AlbumPhotoModel.fromJson(Map<String, dynamic> json) {
    return AlbumPhotoModel(
      id: json['id'] as String,
      albumId: json['album_id'] as String,
      userId: json['user_id'] as String,
      photoUrl: json['photo_url'] as String,
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'album_id': albumId,
      'user_id': userId,
      'photo_url': photoUrl,
      if (caption != null && caption!.isNotEmpty) 'caption': caption,
    };
  }
}

/// Item del feed de fotos: foto + info del álbum + info del usuario
class PhotoFeedItem {
  final String photoId;
  final String photoUrl;
  final String? caption;
  final DateTime createdAt;

  // Info del álbum
  final String albumId;
  final String albumTitle;
  final String albumArtist;
  final String? albumCoverUrl;

  // Info del usuario
  final String userId;
  final String userDisplayName;
  final String? userPhotoUrl;
  final String? userUsername;

  const PhotoFeedItem({
    required this.photoId,
    required this.photoUrl,
    this.caption,
    required this.createdAt,
    required this.albumId,
    required this.albumTitle,
    required this.albumArtist,
    this.albumCoverUrl,
    required this.userId,
    required this.userDisplayName,
    this.userPhotoUrl,
    this.userUsername,
  });

  factory PhotoFeedItem.fromJson(Map<String, dynamic> json) {
    final album = json['albums'] as Map<String, dynamic>? ?? {};
    final user = json['users'] as Map<String, dynamic>? ?? {};

    return PhotoFeedItem(
      photoId: json['id'] as String,
      photoUrl: json['photo_url'] as String,
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      albumId: json['album_id'] as String,
      albumTitle: album['title'] as String? ?? 'Desconocido',
      albumArtist: album['artist'] as String? ?? 'Desconocido',
      albumCoverUrl: album['cover_url'] as String?,
      userId: json['user_id'] as String,
      userDisplayName: user['display_name'] as String? ?? 'Usuario',
      userPhotoUrl: user['photo_url'] as String?,
      userUsername: user['username'] as String?,
    );
  }
}
