import 'package:flutter/foundation.dart';

import 'user_model.dart';

class AuthData {
  final UserModel? profile;
  final bool loading;
  final String? error;
  final bool signingOut;
  final String? uid;
  final bool isSignedIn;
  final bool isAnonymous;
  final bool dummySessionActive;
  final bool emailConfirmed;
  final String? userEmail;
  final bool hasPassword;
  final bool isRealAdmin;
  final bool anonBlocked;
  final bool anonTimelineBlocked;
  final bool screenshotEnabled;
  final bool watermarkEnabled;
  final bool invisibleEnabled;
  final bool reengageEnabled;
  final bool requireRegistration;
  final bool callAllEnabled;
  final bool callAnonEnabled;
  final String appFontFamily;
  final List<String> excludedDevices;
  final bool notificationsEnabled;

  const AuthData({
    this.profile,
    this.loading = true,
    this.error,
    this.signingOut = false,
    this.uid,
    this.isSignedIn = false,
    this.isAnonymous = false,
    this.dummySessionActive = false,
    this.emailConfirmed = false,
    this.userEmail,
    this.hasPassword = false,
    this.isRealAdmin = false,
    this.anonBlocked = false,
    this.anonTimelineBlocked = false,
    this.screenshotEnabled = true,
    this.watermarkEnabled = false,
    this.invisibleEnabled = false,
    this.reengageEnabled = true,
    this.requireRegistration = false,
    this.callAllEnabled = false,
    this.callAnonEnabled = false,
    this.appFontFamily = 'default',
    this.excludedDevices = const [],
    this.notificationsEnabled = true,
  });

  @override
  bool operator ==(Object other) =>
      other is AuthData &&
      other.profile == profile &&
      other.loading == loading &&
      other.error == error &&
      other.signingOut == signingOut &&
      other.uid == uid &&
      other.isSignedIn == isSignedIn &&
      other.isAnonymous == isAnonymous &&
      other.dummySessionActive == dummySessionActive &&
      other.emailConfirmed == emailConfirmed &&
      other.userEmail == userEmail &&
      other.hasPassword == hasPassword &&
      other.isRealAdmin == isRealAdmin &&
      other.anonBlocked == anonBlocked &&
      other.anonTimelineBlocked == anonTimelineBlocked &&
      other.screenshotEnabled == screenshotEnabled &&
      other.watermarkEnabled == watermarkEnabled &&
      other.invisibleEnabled == invisibleEnabled &&
      other.reengageEnabled == reengageEnabled &&
      other.requireRegistration == requireRegistration &&
      other.callAllEnabled == callAllEnabled &&
      other.callAnonEnabled == callAnonEnabled &&
      other.appFontFamily == appFontFamily &&
      other.notificationsEnabled == notificationsEnabled &&
      listEquals(other.excludedDevices, excludedDevices);

  @override
  int get hashCode => Object.hashAll([
    profile,
    loading,
    error,
    signingOut,
    uid,
    isSignedIn,
    isAnonymous,
    dummySessionActive,
    emailConfirmed,
    userEmail,
    hasPassword,
    isRealAdmin,
    anonBlocked,
    anonTimelineBlocked,
    screenshotEnabled,
    watermarkEnabled,
    invisibleEnabled,
    reengageEnabled,
    requireRegistration,
    callAllEnabled,
    callAnonEnabled,
    appFontFamily,
    notificationsEnabled,
    Object.hashAll(excludedDevices),
  ]);
}
