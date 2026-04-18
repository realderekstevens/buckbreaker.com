import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/screener_screen.dart';
import 'screens/game_screen.dart';
import 'screens/stock_detail_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authService = AuthService();
  await authService.init();
  runApp(TraderDudeApp(auth: authService));
}

class TraderDudeApp extends StatelessWidget {
  final AuthService auth;
  const TraderDudeApp({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    final apiClient    = ApiClient(auth);
    final stockService = StockService(apiClient);
    final gameService  = GameService(apiClient);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider.value(value: apiClient),
        Provider.value(value: stockService),
        Provider.value(value: gameService),
      ],
      child: MaterialApp(
        title:        'TraderDude',
        theme:        buildAppTheme(),
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        routes: {
          '/': (ctx) => const _AppShell(),
          '/login': (ctx) => LoginScreen(
            onSuccess: () => Navigator.pushReplacementNamed(ctx, '/'),
          ),
        },
        onGenerateRoute: (settings) {
          // /stocks/AAPL → StockDetailScreen
          final match = RegExp(r'^/stocks/([A-Z0-9.\-]+)$', caseSensitive: false)
              .firstMatch(settings.name ?? '');
          if (match != null) {
            return MaterialPageRoute(
              builder: (_) => StockDetailScreen(
                  symbol: match.group(1)!.toUpperCase()),
            );
          }
          return null;
        },
      ),
    );
  }
}

// ── Shell: bottom nav + tab pages ─────────────────────────────────────────────
class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _idx = 0;

  static const _pages = [
    DashboardScreen(),
    ScreenerScreen(),
    GameScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      // ── Top search bar ─────────────────────────────────────────────────
      appBar: _idx == 0 ? AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [AppColors.accent, AppColors.gold],
            ).createShader(b),
            child: const Icon(Icons.anchor_rounded, color: Colors.white, size: 22),
          ),
        ),
        title: const _SearchBar(),
        actions: [
          IconButton(
            icon: auth.isLoggedIn
                ? const Icon(Icons.account_circle_outlined)
                : const Icon(Icons.login_rounded),
            onPressed: () {
              if (auth.isLoggedIn) {
                _showProfileSheet(context, auth);
              } else {
                Navigator.pushNamed(context, '/login');
              }
            },
          ),
        ],
      ) : null,
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Markets',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.filter_list_rounded),
            label: 'Screener',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sailing_rounded),
            label: 'Patrician',
          ),
        ],
      ),
    );
  }

  void _showProfileSheet(BuildContext context, AuthService auth) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.account_circle_outlined,
                  color: AppColors.accent, size: 40),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(auth.email ?? '',
                  style: AppTextStyles.title),
                Text(auth.role ?? 'app_user',
                  style: AppTextStyles.monoSm.copyWith(
                      color: AppColors.accent)),
              ]),
            ]),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: AppColors.neg, size: 20),
              title: const Text('Sign Out',
                style: TextStyle(color: AppColors.neg)),
              onTap: () {
                Navigator.pop(context);
                auth.logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Global search bar ──────────────────────────────────────────────────────────
class _SearchBar extends StatefulWidget {
  const _SearchBar();
  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() { _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _ctrl,
    focusNode: _focus,
    style: AppTextStyles.mono.copyWith(fontSize: 14),
    decoration: InputDecoration(
      hintText:      'Search symbol…',
      hintStyle:     AppTextStyles.monoSm.copyWith(color: AppColors.text3),
      prefixIcon:    const Icon(Icons.search_rounded, size: 18,
          color: AppColors.text3),
      suffixIcon: _ctrl.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear_rounded, size: 16),
              onPressed: () { _ctrl.clear(); setState(() {}); })
          : null,
      filled:        true,
      fillColor:     AppColors.bg3,
      border:        OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide:   const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide:   const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide:   const BorderSide(color: AppColors.accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      isDense: true,
    ),
    onChanged: (_) => setState(() {}),
    onSubmitted: (v) {
      final sym = v.trim().toUpperCase();
      if (sym.isNotEmpty) {
        _ctrl.clear(); _focus.unfocus();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => StockDetailScreen(symbol: sym)));
      }
    },
  );
}
