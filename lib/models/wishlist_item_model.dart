/// Modelo de un item de la wishlist (disco deseado)
class WishlistItemModel {
  final String id;
  final String userId;
  final String title;
  final String artist;
  final String? coverUrl;
  final int? year;
  final int? discogsId;
  final String? note;
  final DateTime createdAt;

  const WishlistItemModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.year,
    this.discogsId,
    this.note,
    required this.createdAt,
  });

  factory WishlistItemModel.fromJson(Map<String, dynamic> json) {
    return WishlistItemModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      coverUrl: json['cover_url'] as String?,
      year: json['year'] as int?,
      discogsId: json['discogs_id'] as int?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'user_id': userId,
      'title': title,
      'artist': artist,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (year != null) 'year': year,
      if (discogsId != null) 'discogs_id': discogsId,
      if (note != null) 'note': note,
    };
  }

  WishlistItemModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? artist,
    String? coverUrl,
    int? year,
    int? discogsId,
    String? note,
    DateTime? createdAt,
  }) {
    return WishlistItemModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      coverUrl: coverUrl ?? this.coverUrl,
      year: year ?? this.year,
      discogsId: discogsId ?? this.discogsId,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Texto formateado
  String get displayName => '$artist - $title';
}
