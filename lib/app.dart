import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/room_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/online_users_provider.dart';
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
        ChangeNotifierProvider(create: (_) => RoomProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => OnlineUsersProvider()),
      ],
      child: MaterialApp(
        title: 'ChatYuk',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorKey: navigatorKey,
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Menghubungkan...', style: TextStyle(color: AppTheme.textSecondary)),
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
    LobbyScreen(),
    PrivateChatsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = context.read<AuthProvider>();
    auth.goOnline();
    final uid = auth.uid;
    if (uid != null) {
      context.read<ChatProvider>().loadBlockedUids(uid);
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    return Scaffold(
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => context.read<AuthProvider>().notifyActivity(),
        onPointerMove: (_) => context.read<AuthProvider>().notifyActivity(),
        child: _pages[_tab],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.wifi_tethering), label: 'Online'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Rooms'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Private'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
