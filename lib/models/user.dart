class User {
  final int? id;
  final String? uuid;
  final String username;
  final String email;
  final String? password;
  final String? accessToken;
  final String? refreshToken;
  final String? firstName;
  final String? lastName;
  final String? telephoneMobile;
  final String? statut;
  final String? role;
  final String? porteEntree;
  final int? porteEntreeId;
  final bool isSuperuser;
  final bool isStaff;
  final bool isActive;
  final bool isConnected;
  final DateTime? lastLogin;
  final DateTime? dateJoined;

  User({
    this.id,
    this.uuid,
    required this.username,
    this.email = '',
    this.password,
    this.accessToken,
    this.refreshToken,
    this.firstName,
    this.lastName,
    this.telephoneMobile,
    this.statut,
    this.role,
    this.porteEntree,
    this.porteEntreeId,
    this.isSuperuser = false,
    this.isStaff = false,
    this.isActive = true,
    this.isConnected = false,
    this.lastLogin,
    this.dateJoined,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'username': username,
      'email': email,
      'password': password,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'first_name': firstName,
      'last_name': lastName,
      'telephone_mobile': telephoneMobile,
      'statut': statut,
      'role': role,
      'porte_entree': porteEntree,
      'porte_entree_id': porteEntreeId,
      'is_superuser': isSuperuser ? 1 : 0,
      'is_staff': isStaff ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'is_connected': isConnected ? 1 : 0,
      'last_login': lastLogin?.toIso8601String(),
      'date_joined': dateJoined?.toIso8601String(),
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      uuid: map['uuid'] as String?,
      username: map['username'] as String? ?? '',
      email: map['email'] as String? ?? '',
      password: map['password'] as String?,
      accessToken: map['access_token'] as String?,
      refreshToken: map['refresh_token'] as String?,
      firstName: map['first_name'] as String?,
      lastName: map['last_name'] as String?,
      telephoneMobile: map['telephone_mobile'] as String?,
      statut: map['statut'] as String?,
      role: map['role'] as String?,
      porteEntree: map['porte_entree'] as String?,
      porteEntreeId: map['porte_entree_id'] as int?,
      isSuperuser: (map['is_superuser'] as int?) == 1,
      isStaff: (map['is_staff'] as int?) == 1,
      isActive: (map['is_active'] as int?) == 1,
      isConnected: (map['is_connected'] as int?) == 1,
      lastLogin: map['last_login'] != null
          ? DateTime.tryParse(map['last_login'] as String)
          : null,
      dateJoined: map['date_joined'] != null
          ? DateTime.tryParse(map['date_joined'] as String)
          : null,
    );
  }

  factory User.fromJson(Map<String, dynamic> json,
      {String? accessToken, String? refreshToken}) {
    return User(
      id: json['id'] as int?,
      uuid: json['uuid'] as String?,
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      telephoneMobile: json['telephone_mobile'] as String?,
      statut: json['statut'] as String?,
      role: json['role'] as String?,
      porteEntree: json['porte_entree'] as String?,
      porteEntreeId: json['porte_entree_id'] as int?,
      isSuperuser: json['is_superuser'] as bool? ?? false,
      isStaff: json['is_staff'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      accessToken: accessToken ?? json['access'] as String?,
      refreshToken: refreshToken ?? json['refresh'] as String?,
      isConnected: true,
      lastLogin: json['last_login'] != null
          ? DateTime.tryParse(json['last_login'] as String)
          : DateTime.now(),
      dateJoined: json['date_joined'] != null
          ? DateTime.tryParse(json['date_joined'] as String)
          : null,
    );
  }

  User copyWith({
    int? id,
    String? uuid,
    String? username,
    String? email,
    String? password,
    String? accessToken,
    String? refreshToken,
    String? firstName,
    String? lastName,
    String? telephoneMobile,
    String? statut,
    String? role,
    String? porteEntree,
    int? porteEntreeId,
    bool? isSuperuser,
    bool? isStaff,
    bool? isActive,
    bool? isConnected,
    DateTime? lastLogin,
    DateTime? dateJoined,
  }) {
    return User(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      username: username ?? this.username,
      email: email ?? this.email,
      password: password ?? this.password,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      telephoneMobile: telephoneMobile ?? this.telephoneMobile,
      statut: statut ?? this.statut,
      role: role ?? this.role,
      porteEntree: porteEntree ?? this.porteEntree,
      porteEntreeId: porteEntreeId ?? this.porteEntreeId,
      isSuperuser: isSuperuser ?? this.isSuperuser,
      isStaff: isStaff ?? this.isStaff,
      isActive: isActive ?? this.isActive,
      isConnected: isConnected ?? this.isConnected,
      lastLogin: lastLogin ?? this.lastLogin,
      dateJoined: dateJoined ?? this.dateJoined,
    );
  }
}
