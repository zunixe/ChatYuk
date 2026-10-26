// Semua string UI aplikasi dalam Bahasa Indonesia dan English.
// Untuk tambah bahasa baru: tambah getter baru di sini.
import '../models/legal_section.dart';

part 'strings_screen_mx.dart';
part 'strings_chat_mx.dart';
part 'strings_auth_mx.dart';
part 'strings_points_mx.dart';
part 'strings_social_mx.dart';


part 'strings_legal_privacy.dart';
part 'strings_legal_privacy_en.dart';
part 'strings_legal_terms.dart';

class S
    with
        SScreenMx,
        SChatMx,
        SAuthMx,
        SPointsMx,
        SSocialMx {
  @override
  final bool isId;
  // ignore: prefer_const_constructors_in_immutables
  S({required this.isId});
}
