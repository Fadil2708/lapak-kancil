# Menyiapkan kelas dan pemantauan Lapak Kancil

Fitur kelas memakai Supabase. Permainan tetap dapat dimainkan offline; tautan kelas dan dashboard guru memerlukan internet.

## 1. Buat project Supabase

1. Buat project di Supabase dan simpan URL project serta **anon/public key**.
2. Buka **SQL Editor**, jalankan seluruh isi `supabase-schema.sql`.
3. Buka **Authentication → Providers → Email**. Aktifkan email/password dan tentukan apakah konfirmasi email diwajibkan.
4. Di pengaturan URL autentikasi Supabase, masukkan domain tempat game di-host ke daftar **Site URL / Redirect URLs**.

## 2. Isi konfigurasi frontend

Edit `supabase-config.js`:

```js
window.LAPAK_SUPABASE_CONFIG = {
  url: 'https://project-id.supabase.co',
  anonKey: 'nilai-anon-public-key'
};
```

URL dan anon/public key memang digunakan di browser. **Jangan pernah** memasukkan `service_role` key, password database, atau secret lain ke file frontend.

## 3. Deploy

Deploy `lapak-kancil.html`, `guru.html`, `supabase-config.js`, dan `supabase-client.js` pada domain yang sama. Setelah konfigurasi selesai:

- Guru membuka `/guru.html`, mendaftar/masuk, membuat kelas, lalu menyalin tautan kelas.
- Murid membuka tautan tersebut dan mengisi nama panggilan. Tidak ada akun murid.
- Guru memilih **Muat murid** pada kelas untuk melihat bintang, level yang sedang dimainkan, dan soal yang sering perlu latihan.
- Tautan kelas dapat dinonaktifkan. Data murid hanya dapat dibaca/dihapus guru pemilik kelas.

Gunakan nama panggilan, bukan nama lengkap atau informasi pribadi anak. Guru dapat menghapus data murid dari dashboard; menghapus kelas di Supabase juga menghapus murid dan progres terkait.

## Catatan sinkronisasi

Murid masih menyimpan progres lengkap lokal seperti sebelumnya. Salinan online berisi ringkasan bintang, level aktif/terakhir, jumlah stiker, dan beberapa kesulitan yang sering muncul. Ringkasan dikirim saat kelas dibuka dan setelah jawaban tercatat; jika offline, sinkronisasi dicoba lagi saat koneksi pulih. Tombol **Muat murid** mengambil data terbaru saat diminta.

Identitas murid terikat ke browser/perangkat dan tautan kelas, bukan akun murid. Murid yang memakai perangkat lain akan muncul sebagai sesi terpisah.

Database menggunakan Row Level Security. Murid mengakses hanya fungsi RPC untuk bergabung dan menyimpan progres; token sesi perangkat disimpan dalam bentuk hash di database. Tabel murid tidak dapat dibaca publik.
