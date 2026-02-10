/// Modelo de Usuario para VinylScout
/// Incluye integración con Discogs para sincronización de colección
class UserModel {
  final String id;
  final String googleId;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? discogsAccessToken;
  final String? discogsUsername;
  final bool isPublic;
  final bool sharePhotos;
  final String? username;
  final String? bio;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.googleId,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.discogsAccessToken,
    this.discogsUsername,
    this.isPublic = false,
    this.sharePhotos = false,
    this.username,
    this.bio,
    required this.createdAt,
  });

  /// Crea un UserModel desde un Map JSON (respuesta de Supabase)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      googleId: json['google_id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      photoUrl: json['photo_url'] as String?,
      discogsAccessToken: json['discogs_access_token'] as String?,
      discogsUsername: json['discogs_username'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      sharePhotos: json['share_photos'] as bool? ?? false,
      username: json['username'] as String?,
      bio: json['bio'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convierte el modelo a un Map para insertar/actualizar en Supabase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'google_id': googleId,
      'email': email,
      'display_name': displayName,
      'photo_url': photoUrl,
      'discogs_access_token': discogsAccessToken,
      'discogs_username': discogsUsername,
      'is_public': isPublic,
      'share_photos': sharePhotos,
      'username': username,
      'bio': bio,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Crea una copia del modelo con campos actualizados
  UserModel copyWith({
    String? id,
    String? googleId,
    String? email,
    String? displayName,
    String? photoUrl,
    String? discogsAccessToken,
    String? discogsUsername,
    bool? isPublic,
    bool? sharePhotos,
    String? username,
    String? bio,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      googleId: googleId ?? this.googleId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      discogsAccessToken: discogsAccessToken ?? this.discogsAccessToken,
      discogsUsername: discogsUsername ?? this.discogsUsername,
      isPublic: isPublic ?? this.isPublic,
      sharePhotos: sharePhotos ?? this.sharePhotos,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Verifica si el usuario tiene Discogs vinculado
  bool get hasDiscogsLinked => 
      discogsAccessToken != null && discogsAccessToken!.isNotEmpty;

  @override
  String toString() {
    return 'UserModel(id: $id, email: $email, displayName: $displayName, hasDiscogs: $hasDiscogsLinked)';
  }
}

// ─────────────────────────────────────────────
// Perfil público (vista simplificada de otro usuario)
// ─────────────────────────────────────────────
class PublicUserProfile {
  final String id;
  final String displayName;
  final String? photoUrl;
  final String? username;
  final String? bio;
  final int albumCount;
  final int followerCount;
  final int followingCount;
  final bool isFollowedByMe;

  PublicUserProfile({
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.username,
    this.bio,
    this.albumCount = 0,
    this.followerCount = 0,
    this.followingCount = 0,
    this.isFollowedByMe = false,
  });

  factory PublicUserProfile.fromJson(Map<String, dynamic> json, {
    int albumCount = 0,
    int followerCount = 0,
    int followingCount = 0,
    bool isFollowedByMe = false,
  }) {
    return PublicUserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String,
      photoUrl: json['photo_url'] as String?,
      username: json['username'] as String?,
      bio: json['bio'] as String?,
      albumCount: albumCount,
      followerCount: followerCount,
      followingCount: followingCount,
      isFollowedByMe: isFollowedByMe,
    );
  }
}
