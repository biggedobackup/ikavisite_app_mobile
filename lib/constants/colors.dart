import 'package:flutter/material.dart';

/// Palette de couleurs partagée dans toute l'application IKASOLUTION.
/// Utilisée par le tableau de bord, le profil, le menu (drawer) et toutes
/// les pages de visites pour garantir une identité visuelle cohérente.
class AppColors {
  AppColors._(); // non instanciable

  /// Bleu principal de la marque IKASOLUTION.
  static const Color ikaBlue = Color(0xFF1270B8);

  /// Rouge d'accent (déconnexion, alertes).
  static const Color ikaRed = Color(0xFFDC2626);

  /// Fond des cartes / surfaces.
  static const Color card = Color(0xFFFFFFFF);

  /// Fond de page et des champs (gris très clair).
  static const Color inputBg = Color(0xFFF8FAFC);

  /// Bordures discrètes.
  static const Color border = Color(0xFFE2E8F0);

  /// Texte principal (presque noir).
  static const Color text = Color(0xFF0F172A);

  /// Texte secondaire / légendes.
  static const Color textMuted = Color(0xFF64748B);

  /// Bleu très clair pour les fonds d'icônes.
  static const Color blueSoft = Color(0xFFEFF6FF);

  // Couleurs supplémentaires pour le scan et l'UI générale
  static const Color blue600 = Color(0xFF2563EB);
  static const Color blue900 = Color(0xFF1E3A8A);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFD97706);
  static const Color info = Color(0xFF0EA5E9);
}
