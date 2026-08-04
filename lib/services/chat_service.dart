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
  }) async {
    final chatId = _chatId(myUid, otherUid);
    await _db.collection('privateChats').doc(chatId).set({
      'participants': [myUid, otherUid],
      'participantNames': {myUid: myName, otherUid: otherName},
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

    await _db.collection('privateChats').doc(chatId).update({
      'lastMessage': type == 'image' ? '[Foto]' : text,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
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
                lastMessage: data['lastMessage'] ?? '',
                lastMessageAt: (data['lastMessageAt'] as dynamic)?.toDate() ?? DateTime.now(),
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
  final String lastMessage;
  final DateTime lastMessageAt;

  PrivateChatInfo({
    required this.chatId,
    required this.participants,
    required this.participantNames,
    required this.lastMessage,
    required this.lastMessageAt,
  });
}
