import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // ── Room Chat ──

  Stream<List<MessageModel>> getRoomMessages(String roomId) {
    return _db
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MessageModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> sendRoomMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
  }) async {
    await _db.collection('rooms').doc(roomId).collection('messages').add({
      'senderId': senderId,
      'senderName': senderName,
      'senderGender': senderGender,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ── Private Chat ──

  String _chatId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Stream<List<MessageModel>> getPrivateChatMessages(String chatId) {
    return _db
        .collection('privateChats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limitToLast(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => MessageModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<String> startPrivateChat({
    required String myUid,
    required String otherUid,
    required String myName,
    required String otherName,
    String myGender = '',
    String otherGender = '',
    String myCountry = '',
    String otherCountry = '',
    int myAge = 0,
    int otherAge = 0,
  }) async {
    final chatId = _chatId(myUid, otherUid);
    await _db.collection('privateChats').doc(chatId).set({
      'participants': [myUid, otherUid],
      'participantNames': {myUid: myName, otherUid: otherName},
      'participantGenders': {myUid: myGender, otherUid: otherGender},
      'participantLocations': {myUid: myCountry, otherUid: otherCountry},
      'participantAges': {myUid: myAge, otherUid: otherAge},
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return chatId;
  }

  Future<void> sendPrivateMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderGender,
    required String text,
    String type = 'text',
    String imageData = '',
    String receiverId = '',
  }) async {
    await _db.collection('privateChats').doc(chatId).collection('messages').add({
      'senderId': senderId,
      'senderName': senderName,
      'senderGender': senderGender,
      'text': text,
      'type': type,
      'imageData': imageData,
      'timestamp': FieldValue.serverTimestamp(),
    });

    final Map<String, dynamic> update = {
      'lastMessage': type == 'image' ? '[Foto]' : text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
    // increment unread count untuk penerima
    if (receiverId.isNotEmpty) {
      update['unreadCounts.$receiverId'] = FieldValue.increment(1);
    }
    await _db.collection('privateChats').doc(chatId).update(update);
  }

  Future<void> markAsRead(String chatId, String uid) async {
    try {
      await _db.collection('privateChats').doc(chatId).update({
        'unreadCounts.$uid': 0,
        'lastReadAt.$uid': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<List<PrivateChatInfo>> getMyPrivateChats(String myUid) {
    return _db
        .collection('privateChats')
        .where('participants', arrayContains: myUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              return PrivateChatInfo(
                chatId: doc.id,
                participants: List<String>.from(data['participants']),
                participantNames: Map<String, String>.from(data['participantNames'] ?? {}),
                participantGenders: Map<String, String>.from(data['participantGenders'] ?? {}),
                participantLocations: Map<String, String>.from(data['participantLocations'] ?? {}),
                participantAges: Map<String, int>.from(
                  (data['participantAges'] as Map<dynamic, dynamic>? ?? {}).map(
                    (k, v) => MapEntry(k.toString(), (v as num).toInt()),
                  ),
                ),
                lastMessage: data['lastMessage'] ?? '',
                lastMessageAt: (data['lastMessageAt'] as dynamic)?.toDate() ?? DateTime.now(),
                unreadCounts: Map<String, int>.from(
                  (data['unreadCounts'] as Map<dynamic, dynamic>? ?? {}).map(
                    (k, v) => MapEntry(k.toString(), (v as num).toInt()),
                  ),
                ),
                lastReadAt: Map<String, DateTime>.from(
                  (data['lastReadAt'] as Map<dynamic, dynamic>? ?? {}).map(
                    (k, v) => MapEntry(k.toString(), (v as dynamic)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0)),
                  ),
                ),
              );
            }).toList());
  }

  // ── Online Users ──

  Stream<List<UserModel>> getOnlineUsers() {
    return _rtdb.ref('presence').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <UserModel>[];
      return data.entries
          .where((e) {
            final val = Map<String, dynamic>.from(e.value as Map);
            return val['online'] == true;
          })
          .map((e) {
            final val = Map<String, dynamic>.from(e.value as Map);
            return UserModel.fromMap(e.key as String, val);
          })
          .toList();
    });
  }

  // ── Online Users in Room ──

  Stream<List<UserModel>> getOnlineUsersInRoom(String roomId) {
    return _rtdb.ref('roomPresence/$roomId').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <UserModel>[];
      return data.entries.map((e) {
        final val = Map<String, dynamic>.from(e.value as Map);
        return UserModel.fromMap(e.key as String, val);
      }).toList();
    });
  }

  Future<void> joinRoom(String roomId, UserModel user) async {
    // Tandai membership (dipakai pusher untuk notif pesan room)
    await _db.collection('roomMemberships').doc('${roomId}_${user.uid}').set({
      'roomId': roomId,
      'uid': user.uid,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final ref = _rtdb.ref('roomPresence/$roomId/${user.uid}');
    await ref.set({
      'nickname': user.nickname,
      'gender': user.gender,
      'age': user.age,
    });
    // Bersihkan otomatis jika koneksi putus tanpa leaveRoom
    ref.onDisconnect().remove();
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _rtdb.ref('roomPresence/$roomId/$uid').remove();
  }

  Stream<Map<String, int>> getRoomOnlineCounts() {
    return _rtdb.ref('roomPresence').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return <String, int>{};
      return data.map((roomId, users) =>
          MapEntry(roomId as String, (users as Map).length));
    });
  }

  // ── Block / Report ──

  Future<void> blockUser(String myUid, String blockedUid) async {
    await _db.collection('blocks').doc(myUid).collection('blocked').doc(blockedUid).set({
      'blockedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
  }) async {
    await _db.collection('reports').add({
      'reporterId': reporterId,
      'reportedId': reportedId,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isUserBlocked(String myUid, String otherUid) async {
    final doc = await _db.collection('blocks').doc(myUid).collection('blocked').doc(otherUid).get();
    return doc.exists;
  }

  Future<List<String>> getBlockedUids(String myUid) async {
    final snap = await _db.collection('blocks').doc(myUid).collection('blocked').get();
    return snap.docs.map((d) => d.id).toList();
  }
}

class PrivateChatInfo {
  final String chatId;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String> participantGenders;
  final Map<String, String> participantLocations;
  final Map<String, int> participantAges;
  final String lastMessage;
  final DateTime lastMessageAt;
  final Map<String, int> unreadCounts;
  final Map<String, DateTime> lastReadAt;

  PrivateChatInfo({
    required this.chatId,
    required this.participants,
    required this.participantNames,
    this.participantGenders = const {},
    this.participantLocations = const {},
    this.participantAges = const {},
    required this.lastMessage,
    required this.lastMessageAt,
    this.unreadCounts = const {},
    this.lastReadAt = const {},
  });
}
