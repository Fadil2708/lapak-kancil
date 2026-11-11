# Menyiapkan kelas dan pemantauan Lapak Kancil

Fitur kelas memakai Supabase. Permainan tetap dapat dimainkan offline; tautan kelas dan dashboard guru memerlukan internet.

## 1. Buat project Supabase

1. Buat project di Supabase dan simpan URL project serta **anon/public key**.
2. Buka **SQL Editor**, jalankan seluruh isi `supabase-schema.sql`. Jalankan ulang skrip terbaru agar tabel notifikasi masuk ke publikasi Realtime, kolom versi reset, dan fungsi persetujuan tersedia di project yang sudah dipakai.
3. Buka **Authentication → Providers → Email**. Aktifkan email/password dan tentukan apakah konfirmasi email diwajibkan.
4. Di **Authentication → URL Configuration**:
   - Set **Site URL** ke domain utama Vercel, misalnya `https://nama-proyek.vercel.app`.
   - Tambahkan `https://nama-proyek.vercel.app/guru.html?konfirmasi=berhasil` dan `https://nama-proyek.vercel.app/guru.html?aksi=reset` ke **Redirect URLs**. Ganti domain dengan domain deploy kamu. Jika memakai domain preview atau domain sendiri, daftarkan URL callback untuk domain tersebut juga.

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
- Setelah mendaftar, guru mendapat layar konfirmasi email dengan opsi kirim ulang. Tautan email kembali ke `/guru.html`; jika konfirmasi tidak membuat sesi login otomatis, guru bisa masuk dari halaman tersebut.
- Pada portal guru, pilih **Lupa kata sandi?** untuk meminta email pemulihan; tautannya membuka formulir untuk menyimpan kata sandi baru.
- Murid membuka tautan tersebut dan mengisi nama panggilan. Tidak ada akun murid.
- Guru memilih **Muat murid** pada kelas untuk melihat bintang, level yang sedang dimainkan, dan soal yang sering perlu latihan.
- Untuk murid dari tautan kelas, permintaan reset tampil di **Notifikasi kelas** portal guru secara realtime. Murid harus online untuk mengirim permintaan. Progres baru dihapus dari server setelah guru menyetujui; penolakan mempertahankan progres lama. Keputusan muncul di game murid secara realtime, lalu progres disinkronkan ulang.
- Tombol **Aktifkan notifikasi browser** (portal guru) dan **Aktifkan notifikasi** (game murid) meminta izin notifikasi sistem. Notifikasi langsung memerlukan halaman terkait tetap terbuka; bila halaman ditutup, keputusan akan terlihat saat dibuka dan tersinkron kembali.
- Tautan kelas dapat dinonaktifkan. Data murid hanya dapat dibaca/dihapus guru pemilik kelas.

Gunakan nama panggilan, bukan nama lengkap atau informasi pribadi anak. Guru dapat menghapus data murid dari dashboard; menghapus kelas di Supabase juga menghapus murid dan progres terkait.

## Catatan sinkronisasi

Murid masih menyimpan progres lengkap lokal seperti sebelumnya. Salinan online berisi ringkasan bintang, level aktif/terakhir, jumlah stiker, dan beberapa kesulitan yang sering muncul. Ringkasan dikirim saat kelas dibuka dan setelah jawaban tercatat; jika offline, sinkronisasi dicoba lagi saat koneksi pulih. Tombol **Muat murid** mengambil data terbaru saat diminta.

Identitas murid terikat ke browser/perangkat dan tautan kelas, bukan akun murid. Murid yang memakai perangkat lain akan muncul sebagai sesi terpisah. Untuk reset murid kelas, notifikasi Realtime memberi tahu portal guru saat permintaan masuk dan game saat keputusan dibuat; versi progres di server memastikan salinan lokal lama dibersihkan saat tersinkron. Saat perangkat offline, permintaan/persetujuan menunggu koneksi.

Database menggunakan Row Level Security. Murid mengakses fungsi RPC untuk bergabung, menyinkronkan progres, dan meminta reset; token sesi perangkat disimpan dalam bentuk hash di database. Guru hanya dapat melihat dan meninjau permintaan reset di kelas miliknya. Tabel murid tidak dapat dibaca publik.

## Template email Supabase

Di **Authentication → Email Templates**, edit **Confirm signup** dan **Reset Password**. Pertahankan `{{ .ConfirmationURL }}` di tombol pada masing-masing template supaya tautan sekali pakai Supabase tetap berfungsi.

**Confirm signup** — subject: `Satu langkah lagi untuk membuka Lapak Kancil`

```html
<!doctype html>
<html lang="id">
<body style="margin:0;padding:0;background-color:#f6e5c3;font-family:Arial,Helvetica,sans-serif;color:#3b2214">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0">Konfirmasi alamat email untuk mengaktifkan akun guru Lapak Kancil.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#f6e5c3">
    <tr><td align="center" style="padding:32px 12px">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background-color:#fff5de;border:3px solid #3b2214;border-radius:18px">
        <tr><td align="center" style="padding:26px 24px 12px">
          <div style="display:inline-block;padding:8px 16px;background-color:#f3b61f;border:2px solid #3b2214;border-radius:12px;font-size:13px;font-weight:bold;letter-spacing:2px">PASAR PAGI SUDAH RAMAI!</div>
          <h1 style="margin:18px 0 8px;font-size:34px;line-height:1.15;color:#d94a2b">Selamat datang<br>di Lapak Kancil!</h1>
          <p style="margin:0;font-size:16px;line-height:1.6">Satu langkah lagi sebelum kamu membuka kelas dan menemani murid belajar berhitung.</p>
        </td></tr>
        <tr><td align="center" style="padding:18px 24px">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" bgcolor="#f3b61f" style="border:2px solid #3b2214;border-radius:10px">
            <a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:14px 24px;color:#3b2214;text-decoration:none;font-size:17px;font-weight:bold">Konfirmasi alamat email</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="padding:0 28px 24px;font-size:14px;line-height:1.65">
          <p style="margin:0 0 12px">Kalau tombol tidak bisa dibuka, salin tautan ini ke browser:</p>
          <p style="margin:0 0 18px;word-break:break-all"><a href="{{ .ConfirmationURL }}" style="color:#a92f1a">{{ .ConfirmationURL }}</a></p>
          <p style="margin:0">Jika kamu tidak membuat akun Lapak Kancil, abaikan email ini. Akun tidak akan aktif tanpa konfirmasi.</p>
        </td></tr>
        <tr><td align="center" style="padding:16px 20px;background-color:#f3b61f;border-top:2px solid #3b2214;border-radius:0 0 14px 14px;font-size:12px;color:#3b2214">
          Lapak Kancil · Belajar berhitung sambil bermain
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
```

**Reset Password** — subject: `Tautan untuk mengatur ulang kata sandi Lapak Kancil`

```html
<!doctype html>
<html lang="id">
<body style="margin:0;padding:0;background-color:#f6e5c3;font-family:Arial,Helvetica,sans-serif;color:#3b2214">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0">Gunakan tautan aman untuk membuat kata sandi baru akun Lapak Kancil.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#f6e5c3">
    <tr><td align="center" style="padding:32px 12px">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:560px;background-color:#fff5de;border:3px solid #3b2214;border-radius:18px">
        <tr><td align="center" style="padding:26px 24px 12px">
          <div style="display:inline-block;padding:8px 16px;background-color:#f3b61f;border:2px solid #3b2214;border-radius:12px;font-size:13px;font-weight:bold;letter-spacing:2px">LAPAK KANCIL</div>
          <h1 style="margin:18px 0 8px;font-size:34px;line-height:1.15;color:#d94a2b">Kita bantu<br>atur ulang, ya!</h1>
          <p style="margin:0;font-size:16px;line-height:1.6">Kami menerima permintaan untuk membuat kata sandi baru bagi akun guru Lapak Kancil.</p>
        </td></tr>
        <tr><td align="center" style="padding:18px 24px">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr><td align="center" bgcolor="#f3b61f" style="border:2px solid #3b2214;border-radius:10px">
            <a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:14px 24px;color:#3b2214;text-decoration:none;font-size:17px;font-weight:bold">Buat kata sandi baru</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="padding:0 28px 24px;font-size:14px;line-height:1.65">
          <p style="margin:0 0 12px">Kalau tombol tidak bisa dibuka, salin tautan ini ke browser:</p>
          <p style="margin:0 0 18px;word-break:break-all"><a href="{{ .ConfirmationURL }}" style="color:#a92f1a">{{ .ConfirmationURL }}</a></p>
          <p style="margin:0">Jika kamu tidak meminta pengaturan ulang, abaikan email ini. Kata sandimu tidak akan berubah. Jangan bagikan tautan ini kepada siapa pun.</p>
        </td></tr>
        <tr><td align="center" style="padding:16px 20px;background-color:#f3b61f;border-top:2px solid #3b2214;border-radius:0 0 14px 14px;font-size:12px;color:#3b2214">
          Lapak Kancil · Keamanan akun guru
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>
```
