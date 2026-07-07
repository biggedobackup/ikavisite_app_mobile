class ApiConfig {
  static const String baseUrl = 'https://test.ikavisite.com';

  // Timeouts (seconds)
  static const int timeoutDefault = 15;
  static const int timeoutReferences = 8;
  static const int timeoutUpload = 30;

  // Auth
  static const String login = '/api/auth/login';
  static const String refresh = '/api/auth/refresh';
  static const String verify = '/api/auth/verify';
  static const String me = '/api/auth/me';
  static const String logout = '/api/auth/logout';

  // Dashboard
  static const String dashboardStats = '/api/dashboard/stats';

  // Visites
  static const String visites = '/api/visites/';
  static const String visitesEnCours = '/api/visites/en-cours/';
  static const String visitesTerminees = '/api/visites/terminees/';
  static const String visitesExcedees = '/api/visites/excedees/';
  static String visiteById(int id) => '/api/visites/$id';
  static String visiteTerminer(int id) => '/api/visites/$id/terminer';

  // Dropdowns
  static const String typesVisite = '/api/visites/types/';
  static const String portesEntree = '/api/entreprise/portes/';
  static const String departements = '/api/entreprise/departements/';
  static const String personnel = '/api/entreprise/personnel/';
  static const String references = '/api/entreprise/references/';
  static const String visiteurs = '/api/visiteurs/';
  static const String visiteurSearch = '/api/visiteurs/search/';
}
