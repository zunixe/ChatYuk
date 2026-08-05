import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/room_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/online_users_provider.dart';
import 'providers/locale_provider.dart';
import 'main.dart';
import 'screens/entry_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/private_chats_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/online_users_screen.dart';

class ChatYukApp extends StatelessWidget {
  const ChatYukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => localeProvider),
      ],
      child: Consumer<LocaleProvider>(
        builder: (_, __, ___) => MaterialApp(
          title: 'ChatYuk',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          navigatorKey: navigatorKey,
          home: const _AuthGate(),
        ),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    print('[GATE-STATE] initState inst=${auth.instanceId}');
    auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    print('[GATE-STATE] LISTENER FIRED inst=${context.read<AuthProvider>().instanceId} profile=${context.read<AuthProvider>().profile?.uid}');
  }

  @override
  void dispose() {
    context.read<AuthProvider>().removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;
    print('[GATE] loading=${auth.loading} profile=${auth.profile?.uid} error=${auth.error} inst=${auth.instanceId}');

    if (auth.loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(s.loading, style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (auth.error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, color: AppTheme.textSecondary, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Gagal terhubung ke server',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  auth.error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.read<AuthProvider>().retry(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (auth.profile == null) {
      return const EntryScreen();
    }

    try {
      return const _MainNav();
    } catch (e, st) {
      print('[GATE] _MainNav BUILD ERROR: $e\n$st');
      rethrow;
    }
  }
}

class _MainNav extends StatefulWidget {
  const _MainNav();

  @override
  State<_MainNav> createState() => _MainNavState();
}

class _MainNavState extends State<_MainNav> with WidgetsBindingObserver {
  int _tab = 0;
  final _pages = const [
    OnlineUsersScreen(),
    PrivateChatsScreen(),
    LobbyScreen(),
    ProfileScreen(),
  ];

  // Provider dibuat sekali sebagai field — bukan di build()
  final _roomProvider = RoomProvider();
  final _onlineUsersProvider = OnlineUsersProvider();

  @override
  void initState() {
    super.initState();
    print('[MAINNAV] initState');
    WidgetsBinding.instance.addObserver(this);
    final auth = context.read<AuthProvider>();
    try {
      auth.goOnline();
    } catch (e) {
      print('[MAINNAV] goOnline ERROR: $e');
    }
    final uid = auth.uid;
    if (uid != null) {
      try {
        context.read<ChatProvider>().loadBlockedUids(uid);
      } catch (e) {
        print('[MAINNAV] loadBlockedUids ERROR: $e');
      }
    }
  }

  @override
  void dispose() {
    print('[MAINNAV] dispose');
    WidgetsBinding.instance.removeObserver(this);
    _roomProvider.dispose();
    _onlineUsersProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.paused) {
      auth.goOffline();
    } else if (state == AppLifecycleState.resumed) {
      auth.goOnline();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _roomProvider),
        ChangeNotifierProvider.value(value: _onlineUsersProvider),
      ],
      child: Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => context.read<AuthProvider>().notifyActivity(),
          onPanDown: (_) => context.read<AuthProvider>().notifyActivity(),
          child: IndexedStack(
            index: _tab,
            children: _pages,
          ),
        ),
        bottomNavigationBar: _BottomNav(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.wifi_tethering), label: s.navOnline),
        BottomNavigationBarItem(icon: const Icon(Icons.chat_bubble), label: s.navChats),
        BottomNavigationBarItem(icon: const Icon(Icons.chat), label: s.navRooms),
        BottomNavigationBarItem(icon: const Icon(Icons.person), label: s.navProfile),
      ],
    );
  }
}
