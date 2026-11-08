/// Kebijakan verifikasi foto profil berbasis gender.
///
/// Akun FEMALE wajib memakai foto wajah asli: setiap upload foto profil
/// (avatar & slot foto) harus lewat kamera dalam-app + liveness (kedip &
/// toleh) sehingga foto dari galeri, foto orang lain, atau gambar AI tidak
/// bisa dipakai. Akun MALE bebas (galeri/kamera biasa).
bool requiresFaceVerifiedPhoto(String? gender) => gender == 'female';
