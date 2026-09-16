import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'providers/org_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/form/form_screen.dart';
import 'screens/outings_screen.dart';
import 'screens/drafts_screen.dart';
import 'screens/org_selection_screen.dart';
import 'screens/settings/settings_screen.dart';

/// Seed colour - a rich marsh-green used to generate the full M3 palette.
const _kSeedColor = Color(0xFF1B6B3A);

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _kSeedColor,
    brightness: brightness,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,

    // AppBar - flush with the surface, no elevation line while scrolling
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),

    // Cards - outlined, no shadow (cleaner look)
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      color: colorScheme.surface,
    ),

    // Input fields - filled style, rounded corners
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
    ),

    // Filled buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // Elevated buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // Text buttons
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),

    // Chips (used for status badges)
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),

    // Dividers
    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 1,
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
    ),

    // List tiles
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

/// Main app widget
class MassMarshApp extends ConsumerWidget {
  const MassMarshApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final selectedOrg = ref.watch(selectedOrgProvider);
    final orgRestored = ref.watch(orgRestoredProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Salt Marsh Data',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: _resolveHome(auth, selectedOrg, orgRestored),
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          return MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          );
        }
        if (settings.name == '/org-select') {
          return MaterialPageRoute(
            builder: (context) => const OrgSelectionScreen(),
          );
        }
        if (settings.name == '/form') {
          final monitoringType = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => FormScreen(monitoringType: monitoringType),
          );
        }
        if (settings.name == '/sessions') {
          return MaterialPageRoute(
            builder: (context) => const OutingsScreen(),
          );
        }
        if (settings.name == '/drafts') {
          return MaterialPageRoute(
            builder: (context) => const DraftsScreen(),
          );
        }
        if (settings.name == '/settings') {
          return MaterialPageRoute(
            builder: (context) => const SettingsScreen(),
          );
        }
        return null;
      },
    );
  }

  Widget _resolveHome(AuthState auth, dynamic selectedOrg, bool orgRestored) {
    if (!auth.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isAuthenticated) return const LoginScreen();
    // Org restore reads the cached org id then confirms it against a
    // network call - while that's in flight selectedOrg is null too, so
    // without this check every boot (and every process restart Android
    // does behind an external camera/gallery intent) briefly bounces to
    // the org picker even when an org is actually saved
    if (!orgRestored) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (selectedOrg == null) return const OrgSelectionScreen();
    return const HomeScreen();
  }
}
