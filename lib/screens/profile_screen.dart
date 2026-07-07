import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../widgets/skeleton_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Palette partagée avec le dashboard et la page de connexion
  static const Color kIkaBlue = Color(0xFF1270B8);
  static const Color kIkaRed = Color(0xFFDC2626);
  static const Color kCard = Color(0xFFFFFFFF);
  static const Color kInputBg = Color(0xFFF8FAFC);
  static const Color kBorder = Color(0xFFE2E8F0);
  static const Color kText = Color(0xFF0F172A);
  static const Color kTextMuted = Color(0xFF64748B);
  static const Color kBlueSoft = Color(0xFFEFF6FF);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomCtrl;
  late TextEditingController _prenomCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _telephoneCtrl;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    debugPrint('ProfileScreen.initState: user=${user?.username}, firstName=${user?.firstName}, lastName=${user?.lastName}, email=${user?.email}, phone=${user?.telephoneMobile}');
    _nomCtrl = TextEditingController(text: user?.lastName ?? '');
    _prenomCtrl = TextEditingController(text: user?.firstName ?? '');
    _emailCtrl = TextEditingController(
        text: _emailValue(user));
    _telephoneCtrl = TextEditingController(text: user?.telephoneMobile ?? '');
  }

  String _emailValue(User? user) {
    if (user == null) return '';
    if (user.email.isNotEmpty) return user.email;
    return user.username;
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _emailCtrl.dispose();
    _telephoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    await context.read<AuthProvider>().updateProfile(
      lastName: _nomCtrl.text.trim(),
      firstName: _prenomCtrl.text.trim(),
      telephoneMobile: _telephoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );

    if (mounted) {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour')),
      );
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vous déconnecter ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Se déconnecter', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kInputBg,
      appBar: AppBar(
        title: const Text('Mon Profil'),
        backgroundColor: kCard,
        foregroundColor: kText,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_rounded, color: kIkaBlue),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (_, auth, _) {
          final user = auth.user;
          if (user == null) {
            return const ProfileSkeleton();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileHeader(user),
                  const SizedBox(height: 16),
                  _buildSectionTitle('Informations personnelles'),
                  const SizedBox(height: 12),
                  _buildPersonalInfoCard(),
                  if (_isEditing) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: auth.isLoading ? null : _saveProfile,
                        icon: auth.isLoading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(auth.isLoading ? 'Enregistrement…' : 'Enregistrer',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kIkaBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                  if (auth.error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 18, color: kIkaRed),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(auth.error!,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF991B1B))),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Détails du compte'),
                  const SizedBox(height: 12),
                  _buildAccountDetailsCard(user),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text('Se déconnecter',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kCard,
                        foregroundColor: kIkaRed,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFFECACA))),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- En-tête du profil ----
  Widget _buildProfileHeader(User user) {
    final display = user.username.isNotEmpty ? user.username : 'Utilisateur';
    final initial = display[0].toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: kIkaBlue.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: kIkaBlue,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: kIkaBlue.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(display,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kText)),
          if (user.email.isNotEmpty || user.username.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(_emailValue(user),
                style: const TextStyle(fontSize: 12.5, color: kTextMuted)),
          ],
          if (user.statut != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(user.statut!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Titre de section ----
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: kIkaBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
      ],
    );
  }

  // ---- Carte des informations personnelles (formulaire) ----
  Widget _buildPersonalInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: kIkaBlue.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _field(_prenomCtrl, 'Prénom', Icons.person_rounded),
          const SizedBox(height: 14),
          _field(_nomCtrl, 'Nom', Icons.badge_rounded),
          const SizedBox(height: 14),
          _field(_emailCtrl, 'Email', Icons.alternate_email_rounded,
              validator: _isEditing
                  ? (v) => v == null || v.isEmpty ? 'Champ requis' : null
                  : null),
          const SizedBox(height: 14),
          _field(_telephoneCtrl, 'Téléphone', Icons.phone_rounded,
              keyboardType: TextInputType.phone),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
      {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      enabled: _isEditing,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: kText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: kTextMuted),
        prefixIcon: Icon(icon, size: 20, color: kIkaBlue),
        filled: true,
        fillColor: kInputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kIkaBlue, width: 1.5),
        ),
      ),
    );
  }

  // ---- Carte des détails du compte ----
  Widget _buildAccountDetailsCard(User user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: kIkaBlue.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _detailRow(Icons.door_front_door_rounded, 'Porte d\'entrée',
              user.porteEntree ?? 'Non défini'),
          const SizedBox(height: 12),
          _detailRow(Icons.shield_rounded, 'Rôle', user.role ?? 'Non défini'),
          const SizedBox(height: 12),
          _detailRow(Icons.calendar_today_rounded, 'Date de création',
              user.dateJoined != null ? _formatDate(user.dateJoined!) : 'Non disponible'),
          const SizedBox(height: 12),
          _detailRow(Icons.access_time_rounded, 'Dernière connexion',
              user.lastLogin != null ? _formatDate(user.lastLogin!) : 'Jamais'),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: kBlueSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: kIkaBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11.5, color: kTextMuted)),
              const SizedBox(height: 1),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: kText)),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
