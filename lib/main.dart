import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'database/database_helper.dart';
import 'services/http_override.dart';
import 'services/visit_media.dart';
import 'providers/connectivity_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/dashboard_provider.dart';
import 'providers/visit_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/help_screen.dart';
import 'screens/add_visit_screen.dart';
import 'screens/visit_success_screen.dart';
import 'screens/visits_today_screen.dart';
import 'screens/visits_in_progress_screen.dart';
import 'screens/visits_completed_screen.dart';
import 'screens/visits_overdue_screen.dart';
import 'constants/colors.dart';
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = IkaHttpOverrides();
  // Le dossier des images doit être connu avant le premier affichage : les
  // widgets résolvent les références locales de façon synchrone.
  await VisitMedia.ensureRoot();
  // Ouverture (et migrations) de SQLite lancée pendant que la premiere frame
  // se dessine : le splash n'attend plus l'ouverture de la base.
  unawaited(DatabaseHelper().database);
  runApp(const IkaVisiteApp());
}

class IkaVisiteApp extends StatelessWidget {
  const IkaVisiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (ctx) => AuthProvider(ctx.read<ConnectivityProvider>())),
        ChangeNotifierProvider(create: (ctx) => DashboardProvider(ctx.read<ConnectivityProvider>())),
        ChangeNotifierProvider(create: (ctx) => VisitProvider(ctx.read<ConnectivityProvider>())),
        ChangeNotifierProvider(create: (ctx) {
          final auth = ctx.read<AuthProvider>();
          final visits = ctx.read<VisitProvider>();
          return SyncProvider(
            ctx.read<ConnectivityProvider>(),
            () => auth.accessToken,
            onUnauthorized: () async => auth.refreshAccessToken(),
            // Une saisie hors ligne créée côté serveur remplace sa copie
            // locale : sans cela, la copie restait affichée et sa
            // modification échouait.
            onVisiteCreee: (pendingId, visit, terminee, payload) =>
                visits.adoptServerVisit(pendingId, visit,
                    terminee: terminee, payload: payload),
          );
        }),
      ],
      child: MaterialApp(
        title: 'Ika Visite',
        navigatorObservers: [routeObserver],
        debugShowCheckedModeBanner: false, 
        theme: ThemeData(
          scaffoldBackgroundColor: AppColors.inputBg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.ikaBlue,
            primary: AppColors.ikaBlue,
            surface: AppColors.card,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.text,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
          ),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/login': (_) => const LoginScreen(),
          '/dashboard': (_) => const DashboardScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/help': (_) => const HelpScreen(),
          '/add-visit': (_) => const AddVisitScreen(),
          '/visit-success': (_) => const VisitSuccessScreen(),
          '/visits-today': (_) => const VisitsTodayScreen(),
          '/visits-in-progress': (_) => const VisitsInProgressScreen(),
          '/visits-completed': (_) => const VisitsCompletedScreen(),
          '/visits-overdue': (_) => const VisitsOverdueScreen(),
        },
      ),
    );
  }
}
    