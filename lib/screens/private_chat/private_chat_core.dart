part of '../private_chat_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _PcCoreMx on _PrivateChatBase {
  @override
  Widget build(BuildContext context) {
    PerfProbe.buildCount('PrivateChat');
    ref.watch(themeProvider);
    // Koneksi pulih → flush outbox. `ref.listen` WAJIB di build (bukan
    // initState) — Riverpod mengelolanya (aman saat dispose).
    ref.listen<bool>(connectivityProvider, (prev, next) {
      _connOnline = next;
      if (mounted && next) flushOutbox();
    });
    // Rebuild saat status call berubah (overlay video dalam chat muncul/hilang).
    ref.listen(callProvider, (prev, next) {
      if (prev?.activeSession != next.activeSession ||
          prev?.activeMode != next.activeMode ||
          prev?.activeCallId != next.activeCallId) {
        _onCallChanged();
      }
    });
    // HEADER (Prioritas 4): read-receipt (centang-2) di-drive NOTIFIER — hanya
    // subtree list yang rebuild, bukan AppBar/Scaffold. Dulu `_scheduleRebuild`
    // (setState root) tiap lastRead berubah.
    ref.listen<chatRiverpod.ChatHeader>(
      chatRiverpod.chatHeaderProvider(widget.chatId),
      (prev, next) {
        if (prev?.otherLastRead != next.otherLastRead) {
          _lastReadNotifier.value = next.otherLastRead;
        }
      },
    );
    // select per field (bukan watch penuh): heartbeat presence AuthNotifier
    // berubah tiap beberapa detik — watch membuat SELURUH layar chat
    // rebuild tiap kali. Field yang dipakai render tercantum di bawah.
    final callAllEnabled = ref.watch(
      authProvider.select((a) => a.callAllEnabled),
    );
    final meRegistered = ref.watch(
      authProvider.select((a) => a.profile?.isRegistered ?? false),
    );
    final myUid = ref.watch(authProvider.select((a) => a.uid));
    final chat = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(chatRiverpod.chatProvider.notifier);
    // select: rebuild hanya saat isBlocked untuk UID lawan bicara berubah
    final isBlocked = ref.watch(
      chatRiverpod.chatProvider.select((c) => c.isBlocked(widget.otherUid)),
    );
    final s = ref.watch(localeProvider).s;
    dlog(
      '[CHAT-BUILD] callAllEnabled=$callAllEnabled '
      'meRegistered=$meRegistered '
      'otherRegistered=$_hdr.otherRegistered/${widget.otherRegistered}',
    );
    // Saat unblock: re-subscribe status realtime
    if (_wasBlocked && !isBlocked) {
      _wasBlocked = false;
      _subscribeStatus();
      _subscribeTyping();
    } else if (!_wasBlocked && isBlocked) {
      _wasBlocked = true;
      _statusSub?.cancel();
      _statusSub = null;
      _typingSub?.cancel();
      _typingSub = null;
    }
    final points = ref.watch(pointsProvider.select((p) => p.points));
    final pointsEnabled = ref.watch(pointsProvider.select((p) => p.enabled));

    // Show online bonus toast jika ada yang nunggu (sekali per buka chat).
    if (!_bonusToastScheduled) {
      _bonusToastScheduled = true;
      Future.microtask(() {
        if (!mounted) return;
        final pp = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(pointsProvider.notifier);
        pp.checkAndShowOnlineToast(context, s.isId);
        pp.checkAndShowStreakToast(context, s.isId);
      });
    }

    return PopScope(
      // Back menutup search dulu, lalu mode seleksi, baru keluar layar.
      // `_backEscape` = katup sekali-pakai anti "back mati permanen".
      canPop: (!inSelection && !_searching) || _backEscape,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Back benar-benar menutup layar: lepas fokus keyboard SEGERA
          // supaya animasi tutup keyboard tidak berebut frame dengan
          // transisi pop (dulu tombol back "kadang ngelag dikit").
          FocusManager.instance.primaryFocus?.unfocus();
          NavJournal.log('back private-chat didPop (tutup layar)');
          _backGuard.reset();
          return;
        }
        // Veto BASI (search sudah tutup & seleksi kosong — dibersihkan
        // konkuren antara evaluasi canPop & callback, mis. rebuild stream)
        // → niat user SUDAH terpenuhi → NO-OP. Force-pop di sini SALAH
        // (insiden 2026-10-11: escape menembus sampai launcher).
        // Escape hanya bila basi yang SAMA berulang (macet beneran).
        if (!_searching && !inSelection) {
          if (_backGuard.shouldEscape('pc:clean')) {
            debugPrint('[NAV] back escape private-chat (macet, paksa pop)');
            NavJournal.log('back private-chat ESCAPE macet (paksa pop)');
            _backEscape = true;
            BackVetoGuard.safePop(context);
          } else {
            NavJournal.log('back private-chat veto basi, abaikan');
          }
          return;
        }
        _backGuard.reset();
        // Jejak diagnosa "back mati": catat kenapa back di-veto.
        debugPrint(
          '[NAV] back veto private-chat searching=$_searching selection=${selectedIds.length}',
        );
        NavJournal.log(
          'back private-chat veto searching=$_searching selection=${selectedIds.length}',
        );
        try {
          if (_searching) {
            _closeSearch();
          } else if (inSelection) {
            clearSelection();
          }
        } catch (e) {
          // Handler melempar + route masih ada & tertahan → escape sekali.
          // Route sudah unmount → tak ada yang perlu dilakukan.
          debugPrint('[NAV] back handler error private-chat: $e');
          if (!mounted) return;
          NavJournal.log('back private-chat ESCAPE error (paksa pop)');
          _backEscape = true;
          BackVetoGuard.safePop(context);
        }
      },
      child: Scaffold(
        extendBody: true,
        // OPAQUE (dulu Colors.transparent) — lihat [privateChatScaffoldBg].
        backgroundColor: privateChatScaffoldBg,
        // FALSE: background chat TIDAK ikut bergeser saat keyboard muncul
        // (satu halaman tetap). List & composer mengatur inset sendiri
        // via viewInsets/MediaQuery — layout konten tidak meng-krem bg.
        resizeToAvoidBottomInset: false,
        appBar: inSelection
            ? buildSelectionAppBar()
            : _searching
            ? _buildSearchAppBar()
            : AppBar(
                toolbarHeight: 56,
                titleSpacing: 0,
                title: Consumer(
                  builder: (context, ref2, _) {
                    final hdr = ref2.watch(
                      chatRiverpod.chatHeaderProvider(widget.chatId),
                    );
                    final effGender = widget.otherGender.isNotEmpty
                        ? widget.otherGender
                        : hdr.otherGender;
                    final effAge = widget.otherAge > 0
                        ? widget.otherAge
                        : hdr.otherAge;
                    final effRegistered =
                        widget.otherRegistered || hdr.otherRegistered;
                    final genderEmoji = effGender == 'male'
                        ? '\u{1F468}'
                        : effGender == 'female'
                        ? '\u{1F469}'
                        : '';
                    final cityPart = hdr.otherCity.isNotEmpty
                        ? hdr.otherCity
                        : widget.otherCity;
                    final countryPart = hdr.otherCountry.isNotEmpty
                        ? hdr.otherCountry
                        : widget.otherCountry;
                    final subtitle = [
                      if (effAge > 0) '\$effAge',
                      if (cityPart.isNotEmpty && cityPart != countryPart)
                        cityPart,
                      if (countryPart.isNotEmpty) countryPart,
                    ].where((e) => e.isNotEmpty).join(', ');
                    final displayStatus = isBlocked
                        ? 'offline'
                        : hdr.otherStatus;
                    return Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            final navKey = navKeyUser(widget.otherUid);
                            if (!tryClaimNav(navKey)) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UserInfoScreen(
                                  userId: widget.otherUid,
                                  fallbackName: widget.otherName,
                                ),
                              ),
                            ).then((_) => releaseNav(navKey));
                          },
                          // PersonAvatar: SAMA PERSIS dengan kartu daftar "Pengguna
                          // Online" (latar tint + ring WARNA GENDER) → warna orang yang
                          // sama konsisten di list Online, header chat, profil, dll.
                          // Badge: titik presence (atau ikon blokir bila diblokir).
                          child: PersonAvatar(
                            uid: widget.otherUid,
                            avatarB64: widget.initialAvatarB64,
                            name: widget.otherName,
                            gender: effGender,
                            size: 40,
                            status: isBlocked ? null : displayStatus,
                            badge: isBlocked
                                ? Container(
                                    padding: EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.danger,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.block,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            widget.otherName,
                                            style: AppText.titleEmphasis
                                                .copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (effRegistered) ...[
                                          SizedBox(width: 4),
                                          VerifiedBadgeForUid(
                                            uid: widget.otherUid,
                                            size: 15,
                                            tooltip: ref
                                                .read(localeProvider)
                                                .s
                                                .phoneVerifiedBadge,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (genderEmoji.isNotEmpty) ...[
                                    Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Text(
                                        genderEmoji,
                                        style: AppText.bodySmall,
                                      ),
                                    ),
                                  ],
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (subtitle.isNotEmpty)
                                          Text(
                                            subtitle,
                                            style: AppText.bodySmall.copyWith(
                                              color: Colors.white70,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        // Baris status/last-seen — lebih kecil & kurus
                                        // dari subtitle di atasnya (micro 10, tanpa bold).
                                        // Hijau saat online, "terakhir dilihat …" saat tidak.
                                        if (!isBlocked &&
                                            hdr.otherStatus == 'online')
                                          Text(
                                            s.statusOnline,
                                            style: AppText.micro.copyWith(
                                              color: AppTheme.online,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          )
                                        else if (!isBlocked &&
                                            hdr.otherLastSeen != null)
                                          Text(
                                            '${s.lastSeenAt} ${formatRelativeTime(hdr.otherLastSeen!, isId: s.isId)}',
                                            style: AppText.micro.copyWith(
                                              color: Colors.white70,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                actions: [
                  // Admin bisa membuka tombol call untuk SEMUA user (termasuk
                  // anon) via app_settings.call_all_enabled — realtime mengikuti
                  // perubahan toggle di panel admin.
                  if (callAllEnabled ||
                      (meRegistered &&
                          (_hdr.otherRegistered || widget.otherRegistered)))
                    PopupMenuButton(
                      padding: EdgeInsets.zero,
                      iconSize: 22,
                      // Rapat ke kanan: perkecil kotak tap IconButton bawaan (48dp)
                      // supaya ikon call dekat ke titik-3. `constraints` BUKAN untuk
                      // ini — field itu mengatur ukuran menu popup, bukan tombol.
                      style: IconButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(32, 44),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(Icons.call, color: Colors.white, size: 22),
                      color: AppTheme.bgCard,
                      tooltip: s.callAudio,
                      onSelected: (val) {
                        if (val == 'audio') {
                          _startCall(context, 'audio', CallMode.fullscreen);
                        } else if (val == 'video') {
                          _startCall(context, 'video', CallMode.chat);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'audio',
                          child: Text(
                            s.callAudio,
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'video',
                          child: Text(
                            s.callVideo,
                            style: TextStyle(color: AppTheme.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  PopupMenuButton(
                    padding: EdgeInsets.zero,
                    iconSize: 24,
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(Icons.more_vert, color: Colors.white),
                    color: AppTheme.bgCard,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (val) {
                      if (val == 'search') {
                        _openSearch();
                      } else if (val == 'follow') {
                        // Dinamis: sudah follow → berhenti ikuti.
                        final social = ProviderScope.containerOf(
                          context,
                          listen: false,
                        ).read(socialProvider.notifier);
                        if (social.isFollowing(widget.otherUid)) {
                          social.unfollow(widget.otherUid);
                          showChatSnack(
                            context,
                            s.snackUnfollowed(widget.otherName),
                          );
                        } else {
                          social.follow(widget.otherUid);
                          showChatSnack(
                            context,
                            s.snackNowFollowing(widget.otherName),
                          );
                        }
                      } else if (val == 'friend') {
                        final social = ProviderScope.containerOf(
                          context,
                          listen: false,
                        ).read(socialProvider.notifier);
                        final messenger = ScaffoldMessenger.of(context);
                        social.sendFriendRequest(widget.otherUid).then((res) {
                          if (!mounted) return;
                          showChatSnackVia(
                            messenger,
                            context,
                            (res == 'pending' || res == 'friends')
                                ? s.friendRequestSentMutual
                                : s.errGeneric,
                          );
                        });
                      } else if (val == 'block') {
                        chat.blockUser(myUid!, widget.otherUid);
                        showChatSnack(
                          context,
                          s.snackBlocked(widget.otherName),
                        );
                      } else if (val == 'report') {
                        _showReportDialog();
                      }
                    },
                    itemBuilder: (_) {
                      final (:following, :friendLocked) = ref.watch(
                        socialProvider.select(
                          (s) => (
                            following: s.isFollowing(widget.otherUid),
                            friendLocked:
                                s.isFriend(widget.otherUid) ||
                                s.isPendingFriendRequest(widget.otherUid),
                          ),
                        ),
                      );
                      // Sudah teman / permintaan terkirim → sembunyikan "Tambah Teman"
                      // (putus teman / batalkan dilakukan di profil, daftar chat, dll).
                      return <PopupMenuEntry<String>>[
                        PopupMenuItem(
                          value: 'search',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.search_rounded, size: 20),
                            title: Text(s.btnSearch),
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem(
                          value: 'follow',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              following
                                  ? Icons.person_remove_rounded
                                  : Icons.person_add_rounded,
                              size: 20,
                            ),
                            title: Text(
                              following ? s.menuUnfollow : s.menuFollow,
                            ),
                          ),
                        ),
                        if (!friendLocked) ...[
                          const PopupMenuDivider(height: 1),
                          PopupMenuItem(
                            value: 'friend',
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.person_add_alt_rounded,
                                size: 20,
                              ),
                              title: Text(s.menuAddFriend),
                            ),
                          ),
                        ],
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem(
                          value: 'block',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.block_rounded,
                              size: 20,
                              color: AppTheme.danger,
                            ),
                            title: Text(
                              s.btnBlock,
                              style: const TextStyle(color: AppTheme.danger),
                            ),
                          ),
                        ),
                        const PopupMenuDivider(height: 1),
                        PopupMenuItem(
                          value: 'report',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.flag_outlined,
                              size: 20,
                              color: Colors.orange,
                            ),
                            title: Text(
                              s.btnReport,
                              style: const TextStyle(color: Colors.orange),
                            ),
                          ),
                        ),
                      ];
                    },
                  ),
                ],
              ),
        // RepaintBoundary AKAR: saat tombol back ditekan, transisi reverse
        // menggeser seluruh layar. Dengan layer ter-cache, GPU tinggal
        // meng-composite (tanpa re-raster list pesan + bubble + background)
        // → tombol back konsisten mulus (dulu "kadang ngelag dikit").
        body: RepaintBoundary(
          child: Stack(
            children: [
              // Background chat — gambar 30% transparan, di-decode sekali di
              // startup (warmChatBackground) lalu render sinkron via RawImage
              // supaya frame pertama langsung final → tidak ada blink.
              // Ditaruh di layer terluar (Positioned.fill) agar TIDAK ikut
              // bergeser saat keyboard muncul (resizeToAvoidBottomInset: false).
              Positioned.fill(
                child: RepaintBoundary(
                  // Background statis: RawImage (opaque) + lapisan warna
                  // bgScreen 45% DI ATASNYA → efek "55% terlihat" TANPA `Opacity`
                  // widget. `Opacity` full-screen memaksa GPU bikin offscreen
                  // layer penuh tiap frame transisi (raster berat = jank buka/
                  // tutup chat). Dua draw sederhana ini jauh lebih murah.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (chatBackgroundImage != null)
                        RawImage(image: chatBackgroundImage, fit: BoxFit.cover)
                      else
                        const SizedBox.shrink(),
                      Container(
                        color: AppTheme.bgScreen.withValues(alpha: 0.45),
                      ),
                    ],
                  ),
                ),
              ),
              // Konten (list + composer). PENTING: jangan baca viewInsets di
              // sini — dulu `Padding(bottom: MediaQuery.viewInsetsOf...)` di level
              // ini membungkus Column(list+composer) → tiap keyboard muncul
              // (viewInsets 0→~300) SELURUH list pesan rebuild = buka keyboard
              // terasa lambat. Insets sekarang hanya membungkus composer (di
              // bawah), list tak ikut rebuild.
              Positioned.fill(
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          // PERF: JANGAN bungkus seluruh ListView dengan
                          // ValueListenableBuilder(_typingState) — dulu itu
                          // me-rebuild SELURUH daftar pesan (items O(n) + semua
                          // MessageBubble + avatar) tiap typing berubah, jadi
                          // "ngetik → semua ke-load ulang → jeda". Sekarang
                          // hanya bubble typing (item index 0) yang di-drive
                          // ValueNotifier — list & bubble lain tak tersentuh.
                          StreamBuilder<List<MessageModel>>(
                            stream: _msgsStreamCtrl.stream,
                            // FRAME PERTAMA LANGSUNG: data awal dari cache memori
                            // (sinkron) → pesan "nempel" sejak frame pertama
                            // (ala WhatsApp), bukan layar kosong lalu muncul.
                            initialData:
                                MessageCache.instance.peekMessages(
                                  cacheKeyFor(widget.chatId),
                                ) ??
                                const <MessageModel>[],
                            builder: (_, snap) {
                              final msgs = snap.data ?? [];
                              // PERF (Fase 3.3): `_pending` biasanya kosong. Jangan
                              // alokasi list gabungan tiap build kalau tidak perlu —
                              // pakai `msgs` apa adanya (identitasnya stabil dari
                              // stream, jadi `_deriveItems` tetap cache-hit).
                              final all = _pending.isEmpty
                                  ? msgs
                                  : [...msgs, ..._pending];
                              // Pesan baru dari lawan bicara = typing selesai.
                              // Matikan bubble via post-frame (anti setState saat build).
                              // Ini otoritatif: pulse telat dari invokasi lama yang
                              // masih jalan tidak bisa menghidupkan bubble lagi
                              // setelah balasan masuk.
                              for (var i = all.length - 1; i >= 0; i--) {
                                final m = all[i];
                                if (m.senderId != widget.otherUid) continue;
                                if (m.id != _lastPartnerMsgId) {
                                  _lastPartnerMsgId = m.id;
                                  _lastPartnerMsgTime = m.timestamp;
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _hideTyping(),
                                  );
                                }
                                break;
                              }
                              // Bubble typing/recording jadi item paling bawah list
                              // (ala WhatsApp) supaya ikut scroll bersama pesan.
                              if (all.isEmpty) {
                                // Chat kosong: hanya bubble typing yang mungkin
                                // tampil → cukup listen ValueNotifier di sini
                                // (murah; chat kosong = tak ada list pesan).
                                return ValueListenableBuilder<int>(
                                  valueListenable: _typingState,
                                  builder: (_, tv, __) {
                                    if (tv == 0) return const SizedBox.shrink();
                                    return ListView(
                                      controller: _scrollCtrl,
                                      reverse: true,
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        12,
                                        10,
                                        12,
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            0,
                                            6,
                                            6,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: ChatTypingBubble(
                                              isRecording: tv == 2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                              // Auto-load foto deferred DIPINDAH ke listener stream
                              // (lihat private_chat_chat.dart _msgsSub) — dulu di sini
                              // (itemBuilder) → tiap rebuild (tiap kirim TEKS) memicu
                              // fetchImage → emit → bubble FOTO ngedip.
                              // Derivasikan deletedIds + items via CACHE (lihat
                              // _deriveItems): hanya dihitung ulang saat list
                              // pesan/pending/locale/hari berubah — bukan tiap
                              // rebuild parent (ngetik/scroll/menu).
                              final now0 = DateTime.now();
                              final day0 = DateTime(
                                now0.year,
                                now0.month,
                                now0.day,
                              );
                              final (items, deletedIds) = _deriveItems(
                                s,
                                msgs,
                                all,
                                day: day0,
                              );
                              PerfProbe.buildCount('ChatList');
                              // Search chat: cocokkan sekali per emission juga
                              // (bukan per bubble). Urutan terbaru-dulu untuk
                              // navigasi ala WhatsApp.
                              final searching =
                                  _searching && _searchQuery.trim().isNotEmpty;
                              _matchIds = searching
                                  ? searchChatMatches(all, _searchQuery)
                                  : const [];
                              _matchSet = _matchIds.toSet();
                              if (_matchIndex >= _matchIds.length) {
                                _matchIndex = 0;
                              }
                              if (searching) {
                                for (final id in _matchIds) {
                                  _searchKeys.putIfAbsent(
                                    id,
                                    () => GlobalKey(),
                                  );
                                }
                                _searchKeys.removeWhere(
                                  (id, _) => !_matchSet.contains(id),
                                );
                              } else if (_searchKeys.isNotEmpty) {
                                _searchKeys.clear();
                              }
                              // `items` (pesan + chip tanggal) sudah dihitung di
                              // _deriveItems (cache) — langsung pakai.
                              return ValueListenableBuilder<DateTime?>(
                                valueListenable: _lastReadNotifier,
                                builder: (_, lastReadValue, __) => ListView.builder(
                                  controller: _scrollCtrl,
                                  reverse: true,
                                  // PERF (mount pertama chat berat): default
                                  // cacheExtent 250px memaksa Flutter pre-build bubble
                                  // DI LUAR viewport (peta/video = berat) saat buka →
                                  // 1-2 frame raster drop ("ngelag pertama"). Perkecil
                                  // ke 120px: cukup untuk scroll mulus, tapi bubble
                                  // jauh (peta/video) tidak ikut di-mount di frame
                                  // pertama. Terukur raster max ~58ms → turun.
                                  cacheExtent: 120,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    12,
                                    10,
                                    12,
                                  ),
                                  // Slot index 0 SELALU ada untuk bubble typing —
                                  // isinya di-drive ValueNotifier (bubble atau
                                  // kosong) sehingga perubahan typing TIDAK
                                  // me-rebuild list/bubble lain.
                                  itemCount: items.length + 1,
                                  itemBuilder: (_, i) {
                                    // Index 0 = paling bawah (list reverse): bubble
                                    // typing/recording nempel di bawah pesan terbaru
                                    // dan ikut scroll seperti bubble biasa.
                                    if (i == 0) {
                                      return ValueListenableBuilder<int>(
                                        valueListenable: _typingState,
                                        builder: (_, tv, __) {
                                          if (tv == 0)
                                            return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              4,
                                              0,
                                              6,
                                              6,
                                            ),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: ChatTypingBubble(
                                                isRecording: tv == 2,
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }
                                    final di = i - 1;
                                    final item = items[items.length - 1 - di];
                                    if (item.dateLabel != null) {
                                      return DateChip(label: item.dateLabel!);
                                    }
                                    final msg = item.msg!;
                                    final isMe = msg.senderId == myUid;
                                    final isPending = msg.id.startsWith(
                                      'pending-',
                                    );
                                    final isRead =
                                        isMe &&
                                        !isPending &&
                                        ReadReceipt.isRead(
                                          msg.timestamp,
                                          _lastReadNotifier.value,
                                        );
                                    // Image kosong & pesan lama (> 50 dari terbaru) → deferred (icon refresh)
                                    final isImageDeferred =
                                        msg.type == 'image' &&
                                        msg.imageData.isEmpty &&
                                        di >= 50;
                                    final searchKey = searching
                                        ? _searchKeys[msg.id]
                                        : null;
                                    // RepaintBoundary per bubble: satu bubble berubah
                                    // (centang, reaksi, foto masuk, animasi like)
                                    // tidak memicu repaint seluruh list — isolasi
                                    // layer per kartu. Pola SAMA dengan monitor admin
                                    // & kartu list lain (chat/online/timeline) yang
                                    // sudah memakainya (docs/PERFORMANCE.md §2.5).
                                    // Dipakai HANYA di jalur bubble chat biasa —
                                    // kartu/typing-wrapper tetap seperti semula.
                                    return RepaintBoundary(
                                      child: MessageBubble(
                                        key: searchKey ?? ValueKey(msg.id),
                                        link: linkFor(msg.id),
                                        msg: msg,
                                        s: s,
                                        searchQuery: searching
                                            ? _searchQuery.trim()
                                            : '',
                                        chatKey: cacheKeyFor(widget.chatId),
                                        isMe: isMe,
                                        isRead: isRead,
                                        isPending: isPending,
                                        isQueued: _queuedIds.contains(msg.id),
                                        isImageDeferred: isImageDeferred,
                                        onRetryImage: _msgsHandleFetchImage,
                                        // Video di luar 50 terbaru → poster tidak
                                        // auto-load (hemat kuota); tap memuat.
                                        // Pola sama seperti isImageDeferred foto.
                                        autoVideoPoster: di < 50,
                                        onLongPressMenu: onMessageLongPress,
                                        // Mode seleksi: tap = tambah/kurangi seleksi.
                                        onTapSelect: inSelection
                                            ? () => toggleSelect(msg)
                                            : null,
                                        selected: selectedIds.contains(msg.id),
                                        reactions: reactions[msg.id],
                                        starred: starredIds.contains(msg.id),
                                        onTapBadge:
                                            reactions[msg.id]?.isNotEmpty ==
                                                true
                                            ? () => openReactionDetail(msg)
                                            : null,
                                        // Geser ke kanan = balas. Hanya pesan lawan
                                        // (gaya WhatsApp) — pesan sendiri tidak,
                                        // supaya tidak bentrok dengan swipe-back
                                        // sistem di iOS. Mati saat mode seleksi.
                                        onSwipeReply:
                                            inSelection || isMe || msg.isDeleted
                                            ? null
                                            : () => replyMessage(msg),
                                        deletedIds: deletedIds,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          if (pointsEnabled)
                            Positioned(
                              top: 8,
                              right: 12,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.15,
                                      ),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '🪙 $points',
                                  style: AppText.label.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _buildBottomBar(context, s, pointsEnabled),
                  ],
                ),
              ),
              if (_showCallOverlay)
                Positioned.fill(
                  child: ChatCallOverlay(
                    session: ProviderScope.containerOf(
                      context,
                      listen: false,
                    ).read(callProvider.notifier).activeSession!,
                    onExpand: _expandCall,
                    onEnd: () => unawaited(
                      ProviderScope.containerOf(
                        context,
                        listen: false,
                      ).read(callProvider.notifier).hangup(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ), // RepaintBoundary
    );
  }
}
