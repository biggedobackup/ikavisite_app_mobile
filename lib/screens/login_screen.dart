import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _remember = true;

  // Palette de la version web
  static const Color kIkaBlue = Color(0xFF1270B8);
  static const Color kIkaRed = Color(0xFFDC2626);
  static const Color kCard = Color(0xFFFFFFFF);
  static const Color kInputBg = Color(0xFFF8FAFC);
  static const Color kBorder = Color(0xFFE2E8F0);
  static const Color kText = Color(0xFF0F172A);
  static const Color kTextMuted = Color(0xFF64748B);
  static const Color kBlueSoft = Color(0xFFEFF6FF);
  static const Color kRedSoft = Color(0xFFFEF2F2);

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  void _showForgotPassword() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: kBlueSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.vpn_key_rounded,
                      color: kIkaBlue, size: 28),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Réinitialisation du mot de passe',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Pour protéger votre compte, contactez l'administrateur IKAVISITE de votre entreprise. Une procédure de réinitialisation sécurisée vous sera envoyée après vérification de votre identité.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: kTextMuted),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kInputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text('Support recommandé',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: kText)),
                    ),
                    Text('support@ikavisite.com',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: kIkaBlue)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kText,
                    side: const BorderSide(color: kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Fermer',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Form(
              key: _formKey,
              child: _formCard(),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Carte du formulaire ----
  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: kIkaBlue.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand : logo et texte centrés
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: kBlueSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(7),
                  child: Image.asset('assets/images/logo.png'),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5),
                        children: [
                          TextSpan(text: 'IKA', style: TextStyle(color: kIkaBlue)),
                          TextSpan(text: 'VISITE', style: TextStyle(color: kIkaRed)),
                        ],
                      ),
                    ),
                    const Text(
                      "Contrôle d'accès & sécurité",
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextMuted,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: kBorder),
          const SizedBox(height: 22),

          const Text(
            'Connexion',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: kText,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Connectez-vous pour superviser les flux d'entrée et de sortie.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: kTextMuted),
          ),
          const SizedBox(height: 22),

          // Champ utilisateur
          _label('Adresse email ou nom d\'utilisateur'),
          const SizedBox(height: 8),
          _input(
            controller: _usernameCtrl,
            hint: 'admin@ikavisite.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                v == null || v.isEmpty ? 'Champ requis' : null,
          ),
          const SizedBox(height: 16),

          // Champ mot de passe
          _label('Mot de passe'),
          const SizedBox(height: 8),
          _input(
            controller: _passwordCtrl,
            hint: '8 caractères minimum',
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePassword,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: kTextMuted,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? 'Champ requis' : null,
          ),
          const SizedBox(height: 14),

          // Erreur
          Consumer<AuthProvider>(
            builder: (_, auth, _) {
              if (auth.error != null) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kRedSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: kIkaRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(auth.error!,
                            style: const TextStyle(
                                fontSize: 12.5, color: kIkaRed)),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Se souvenir / oublié
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => setState(() => _remember = !_remember),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _remember,
                        onChanged: (v) =>
                            setState(() => _remember = v ?? false),
                        activeColor: kIkaBlue,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5)),
                        side: const BorderSide(color: kBorder, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Se souvenir de moi',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: kText)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _showForgotPassword,
                child: const Text(
                  'Mot de passe oublié ?',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: kIkaBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Bouton de connexion
          Consumer<AuthProvider>(
            builder: (_, auth, _) {
              return Opacity(
                opacity: auth.isLoading ? 0.85 : 1,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: auth.isLoading ? null : _submit,
                    child: Ink(
                      decoration: BoxDecoration(
                        color: kIkaBlue,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: kIkaBlue.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.lock_open_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    'Se connecter',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Séparateur sécurisé
          Row(
            children: [
              const Expanded(child: Divider(color: kBorder, thickness: 1)),
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: kBlueSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.shield_rounded,
                    color: kIkaBlue, size: 14),
              ),
              const SizedBox(width: 8),
              const Text(
                'Connexion sécurisée',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kTextMuted,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Divider(color: kBorder, thickness: 1)),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "Vos identifiants sont personnels. Connectez-vous uniquement depuis un appareil de confiance et signalez toute activité inhabituelle.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.5, color: kTextMuted),
          ),
        ],
      ),
    );
  }

  // ---- Helpers UI ----
  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: kText,
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 14.5, color: kText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: kTextMuted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: kInputBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kIkaBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kIkaRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kIkaRed, width: 1.6),
        ),
      ),
    );
  }
}
