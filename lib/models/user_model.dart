/// Modelo de Usuario para VinylFinder
/// Incluye integración con Discogs para sincronización de colección
class UserModel {
  final String id;
  final String googleId;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? discogsAccessToken;
  final String? discogsUsername;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.googleId,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.discogsAccessToken,
    this.discogsUsername,
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
