part of '../profile_screen.dart';

// ignore_for_file: unused_element, unused_element_parameter

mixin _ProfileCoreMx on _ProfileBase {
  void initState() {
    super.initState();
    _loadPhotos();
    _hashtags = List.of(
      ProviderScope.containerOf(
            context,
            listen: false,
          ).read(authProvider.notifier).profile?.hashtags ??
          const [],
    );
    // Onboarding + daily login toast
    Future.microtask(() {
      final pp = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(pointsProvider.notifier);
      final s = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(localeProvider).s;
      pp.refreshEnabled().then((_) => pp.showOnboardingIfNeeded(context, s));
    });
  }

  @override
  void dispose() {
    _hashtagCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  void _startEditAbout(String current) {
    _aboutCtrl.text = current;
    setState(() => _editingAbout = true);
  }

  void _cancelEditAbout() {
    FocusScope.of(context).unfocus();
    setState(() => _editingAbout = false);
  }

  Future<void> _saveAbout() async {
    final auth = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authProvider.notifier);
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final text = _aboutCtrl.text.trim();
    if (text == (auth.profile?.about ?? '')) {
      setState(() => _editingAbout = false);
      return;
    }
    setState(() => _savingAbout = true);
    try {
      await auth.updateProfile(about: text);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        _editingAbout = false;
        _savingAbout = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingAbout = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  void _addHashtag(String raw) {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final tag = raw.trim().replaceAll(RegExp(r'^#+'), '').toLowerCase();
    if (tag.isEmpty) return;
    if (_hashtags.contains(tag)) return;
    if (_hashtags.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errHashtagMax)));
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]{1,20}$').hasMatch(tag)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errHashtagFormat)));
      return;
    }
    final tags = List<String>.of(_hashtags)..add(tag);
    _saveHashtags(tags);
    _hashtagCtrl.clear();
  }

  void _removeHashtag(String tag) {
    final tags = List<String>.of(_hashtags)..remove(tag);
    _saveHashtags(tags);
  }

  Future<void> _saveHashtags(List<String> tags) async {
    final s = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider).s;
    final previous = _hashtags;
    setState(() {
      _hashtags = tags;
      _savingHashtags = true;
    });
    try {
      await ProviderScope.containerOf(
        context,
        listen: false,
      ).read(authProvider.notifier).updateHashtags(tags);
    } catch (e) {
      if (mounted) setState(() => _hashtags = previous);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.errProfileSave)));
      }
    }
    if (mounted) setState(() => _savingHashtags = false);
  }
}
