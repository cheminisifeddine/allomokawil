import 'enums.dart';

/// A registered account. Mirrors `User` from finili types.
class User {
  final int id;
  final String phone;
  final String? email;
  final String fullName;
  final UserRole type;
  final String? avatarUrl;
  final String? wilaya;
  final String? commune;

  const User({
    required this.id,
    required this.phone,
    this.email,
    required this.fullName,
    required this.type,
    this.avatarUrl,
    this.wilaya,
    this.commune,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        phone: json['phone'] as String,
        email: json['email'] as String?,
        fullName: json['full_name'] as String,
        type: UserRole.from(json['type'] as String?),
        avatarUrl: json['avatar_url'] as String?,
        wilaya: json['wilaya'] as String?,
        commune: json['commune'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'email': email,
        'full_name': fullName,
        'type': type.wire,
        'avatar_url': avatarUrl,
        'wilaya': wilaya,
        'commune': commune,
      };
}