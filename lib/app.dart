import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/room_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/online_users_provider.dart';
import 'providers/locale_provider.dart';
import 'services/chat_service.dart';
import 'main.dart';
import 'screens/entry_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/private_chats_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/online_users_screen.dart';
import 'screens/reset_password_screen.dart';

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
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final s = context.watch<LocaleProvider>().s;

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
                const Text(
                  'Periksa koneksi internet kamu, lalu coba lagi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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

    return const _MainNav();
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
    WidgetsBinding.instance.addObserver(this);
    final auth = context.read<AuthProvider>();
    auth.goOnline();
    auth.resetIdleTimer();
    final uid = auth.uid;
    if (uid != null) {
      context.read<ChatProvider>().loadBlockedUids(uid);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roomProvider.dispose();
    _onlineUsersProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.paused) {
      // App di-background/ditutup → set idle, bukan offline.
      // User tetap tampil di menu online sebagai idle, baru hilang saat logout.
      auth.goIdle();
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
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();
    final uid = auth.uid;

    return StreamBuilder<List<PrivateChatInfo>>(
      stream: uid != null ? chat.getMyPrivateChats(uid) : const Stream.empty(),
      builder: (_, snap) {
        final totalUnread = (snap.data ?? []).fold<int>(0, (sum, c) {
          return sum + ((c.unreadCounts[uid] ?? 0));
        });
        return BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          items: [
            BottomNavigationBarItem(icon: const Icon(Icons.wifi_tethering), label: s.navOnline),
            BottomNavigationBarItem(
              icon: _BadgedIcon(icon: Icons.chat_bubble, count: totalUnread),
              label: s.navChats,
            ),
            BottomNavigationBarItem(icon: const Icon(Icons.chat), label: s.navRooms),
            BottomNavigationBarItem(icon: const Icon(Icons.person), label: s.navProfile),
          ],
        );
      },
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgedIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 14),
            decoration: BoxDecoration(
              color: AppTheme.danger,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
