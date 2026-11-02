import 'package:flutter/material.dart';

class L10n {
  const L10n(this.isEnglish);

  final bool isEnglish;

  static L10n of(BuildContext context) =>
      L10n(Localizations.localeOf(context).languageCode == 'en');

  String t(String key, [Map<String, String> args = const {}]) {
    final entry = _strings[key];
    var text = entry == null ? key : (isEnglish ? entry.$2 : entry.$1);
    for (final arg in args.entries) {
      text = text.replaceAll('{${arg.key}}', arg.value);
    }
    return text;
  }

  static const Map<String, (String, String)> _strings = {
    'nav.devices': ('Perangkat', 'Devices'),
    'nav.files': ('Berkas', 'Files'),
    'nav.notes': ('Catatan', 'Notes'),
    'nav.backup': ('Backup', 'Backup'),
    'nav.menu': ('MENU', 'MENU'),
    'app.language': ('Ganti bahasa', 'Change language'),
    'app.profile': ('Profil lokal', 'Local profile'),
    'app.chooseLanguage': ('Pilih bahasa', 'Choose language'),
    'app.indonesian': ('Bahasa Indonesia', 'Indonesian'),
    'app.english': ('English', 'English'),
    'about.title': ('Tentang Drople', 'About Drople'),
    'about.credit': ('Dibuat dengan ❤️ oleh Virza', 'Made with ❤️ by Virza'),
    'profile.title': ('Profil Perangkat', 'Device Profile'),
    'profile.deviceName': ('Nama perangkat', 'Device name'),
    'profile.hint': (
      'Nama ini terlihat oleh perangkat lain saat terhubung.',
      'This name is visible to other devices when connected.',
    ),
    'profile.thisDevice': ('Perangkat ini', 'This device'),
    'peers.thisDevice': ('Perangkat ini', 'This device'),
    'peers.subtitle': (
      '{device} · {count} terhubung',
      '{device} · {count} connected',
    ),
    'peers.addRelay': ('Tambah relay', 'Add relay'),
    'peers.codeTitle': ('Kode Perangkat Anda', 'Your device code'),
    'peers.codeHide': ('Ketuk untuk menyembunyikan', 'Tap to hide'),
    'peers.codeShow': (
      'Ketuk untuk melihat 6 digit pairing',
      'Tap to view the 6-digit pairing code',
    ),
    'peers.copyCode': ('Salin Kode', 'Copy code'),
    'peers.showQr': ('Lihat QR', 'Show QR'),
    'peers.codeCopied': ('Kode pairing disalin', 'Pairing code copied'),
    'peers.useCode': (
      'Gunakan kode dari perangkat lain',
      'Use a code from another device',
    ),
    'peers.scanQr': ('Pindai QR', 'Scan QR'),
    'peers.detect': ('Deteksi Perangkat', 'Device Detection'),
    'peers.online': ('{count} online', '{count} online'),
    'peers.rescan': ('Pindai ulang', 'Rescan'),
    'peers.searchingNearby': (
      'Mencari perangkat di sekitar…',
      'Looking for nearby devices…',
    ),
    'peers.nearby': ('Perangkat Terdekat', 'Nearby Devices'),
    'peers.searchingNetwork': (
      'Mencari perangkat di jaringan yang sama…',
      'Looking for devices on the same network…',
    ),
    'peers.foundAuto': (
      'Ditemukan otomatis lewat Wi-Fi lokal',
      'Found automatically over local Wi-Fi',
    ),
    'peers.emptyTitle': (
      'Belum ada perangkat terdeteksi',
      'No devices detected yet',
    ),
    'peers.emptyMessage': (
      'Buka Drople di perangkat lain pada Wi-Fi yang sama.',
      'Open Drople on another device on the same Wi-Fi.',
    ),
    'peers.scan': ('Pindai', 'Scan'),
    'peers.unnamed': ('Perangkat Tanpa Nama', 'Unnamed device'),
    'peers.connected': ('Terhubung', 'Connected'),
    'peers.lastSeen': ('Terakhir {time}', 'Last seen {time}'),
    'peers.sendFile': ('Kirim Berkas', 'Send File'),
    'peers.disconnect': ('Putuskan', 'Disconnect'),
    'peers.disconnected': (
      'Sambungan dengan {device} diputus',
      'Disconnected from {device}',
    ),
    'peers.disconnectFailed': (
      'Gagal memutus sambungan',
      'Could not disconnect device',
    ),
    'peers.connect': ('Hubungkan', 'Connect'),
    'peers.radarDevice': ('Perangkat', 'Device'),
    'peers.dialogTitle': ('Masukkan Kode', 'Enter Code'),
    'peers.cancel': ('Batal', 'Cancel'),
    'peers.connectAction': ('Hubungkan', 'Connect'),
    'peers.toastSent': ('Permintaan pairing dikirim', 'Pairing request sent'),
    'peers.toastNotFound': (
      'Perangkat dengan kode {code} belum terdeteksi. Pastikan Drople terbuka di perangkat tujuan dan berada di jaringan yang sama.',
      'Device with code {code} was not detected. Make sure Drople is open on the target device and on the same network.',
    ),
    'peers.toastConnectFailed': (
      'Gagal terhubung. Periksa kode lalu coba lagi.',
      'Could not connect. Check the code and try again.',
    ),
    'peers.toastConnectError': (
      'Gagal terhubung ke perangkat',
      'Failed to connect to device',
    ),
    'peers.invalidCode': ('Kode pairing tidak valid', 'Invalid pairing code'),
    'peers.sending': ('Mengirim {file} ke {peer}', 'Sending {file} to {peer}'),
    'peers.sendFailed': ('Gagal mengirim file', 'Failed to send file'),
    'peers.archiveTitle': ('MyFileGua', 'MyFileGua'),
    'peers.archiveSubtitle': (
      'Arsip file pribadi di perangkat ini',
      'Personal file archive on this device',
    ),
    'peers.archiveAdd': ('Simpan file', 'Save files'),
    'peers.archiveEmpty': (
      'Simpan PDF, foto, dan file penting di sini.',
      'Save PDFs, photos, and important files here.',
    ),
    'peers.archiveSaved': (
      'File disimpan ke MyFileGua',
      'Files saved to MyFileGua',
    ),
    'peers.archiveFailed': ('Gagal menyimpan file', 'Could not save files'),
    'peers.archiveDelete': ('Hapus dari arsip', 'Remove from archive'),
    'peers.archiveMore': ('dan {count} file lainnya', 'and {count} more files'),
    'peers.archiveOpen': ('Buka arsip', 'Open archive'),
    'myfile.subtitle': (
      '{count} file tersimpan di perangkat ini',
      '{count} files stored on this device',
    ),
    'myfile.add': ('Tambah file', 'Add files'),
    'myfile.emptyTitle': ('Arsip masih kosong', 'Your archive is empty'),
    'myfile.emptyMessage': (
      'Tambahkan dokumen dan file penting. Catatan pribadi bisa kamu kirim lewat kolom chat di bawah.',
      'Add documents and important files. Send personal notes using the chat box below.',
    ),
    'myfile.saved': (
      'File ditambahkan ke MyFileGua',
      'Files added to MyFileGua',
    ),
    'myfile.failed': ('Gagal menambahkan file', 'Could not add files'),
    'myfile.noteTitle': ('Catatan file', 'File note'),
    'myfile.noteHint': ('Untuk apa file ini?', 'What is this file for?'),
    'myfile.saveNote': ('Simpan catatan', 'Save note'),
    'myfile.cancel': ('Batal', 'Cancel'),
    'myfile.deleteTitle': ('Hapus file?', 'Delete file?'),
    'myfile.deleteMessage': (
      'File {file} akan dihapus dari arsip.',
      'File {file} will be removed from the archive.',
    ),
    'myfile.delete': ('Hapus', 'Delete'),
    'myfile.chatTitle': ('Catatan pribadi', 'Personal notes'),
    'myfile.chatSubtitle': (
      'Simpan pengingat seperti mengirim pesan ke diri sendiri',
      'Save reminders like sending a message to yourself',
    ),
    'myfile.chatEmpty': (
      'Belum ada catatan. Tulis sesuatu di bawah untuk menyimpannya.',
      'No notes yet. Write something below to save it.',
    ),
    'myfile.messageHint': ('Tulis catatan...', 'Write a note...'),
    'myfile.send': ('Kirim catatan', 'Send note'),
    'myfile.attach': ('Lampirkan file', 'Attach files'),
    'myfile.viewFiles': ('File terkirim', 'Sent files'),
    'myfile.fileMissing': (
      'File sudah dihapus dari arsip',
      'File was removed from the archive',
    ),
    'myfile.openFile': ('Ketuk untuk membuka', 'Tap to open'),
    'peers.pairRequestTitle': ('Permintaan koneksi', 'Connection request'),
    'peers.pairRequestMessage': (
      '{device} ingin terhubung ke perangkat ini. Izinkan koneksi?',
      '{device} wants to connect to this device. Allow the connection?',
    ),
    'peers.pairAccept': ('Izinkan', 'Allow'),
    'peers.pairReject': ('Tolak', 'Reject'),
    'peers.pairRejected': (
      'Permintaan koneksi ditolak oleh {device}',
      'Connection request was rejected by {device}',
    ),
    'peers.relayTitle': ('Tambah Relay', 'Add Relay'),
    'peers.relayAdd': ('Tambah', 'Add'),
    'peers.relayAdded': ('Relay ditambahkan', 'Relay added'),
    'peers.relayInvalid': ('Alamat relay tidak valid', 'Invalid relay address'),
    'files.title': ('Berkas', 'Files'),
    'files.subtitle': (
      'Transfer langsung antar-perangkat',
      'Direct device-to-device transfer',
    ),
    'files.connectFirst': (
      'Hubungkan perangkat terlebih dahulu di tab Perangkat',
      'Connect a device first on the Devices tab',
    ),
    'files.sending': ('Mengirim {file} ke {peer}', 'Sending {file} to {peer}'),
    'files.startFailed': (
      'Gagal memulai pengiriman',
      'Failed to start transfer',
    ),
    'files.scanAndroid': (
      'Pemindai QR tersedia di Android',
      'QR scanner is available on Android',
    ),
    'files.invalidCode': ('Kode pairing tidak valid', 'Invalid pairing code'),
    'files.pairSent': ('Permintaan pairing dikirim', 'Pairing request sent'),
    'files.connectFailed': (
      'Gagal terhubung ke perangkat',
      'Failed to connect to device',
    ),
    'files.choosePeer': ('Kirim ke perangkat', 'Send to device'),
    'files.choosePeerHint': (
      'Pilih tujuan transfer file.',
      'Choose a destination for the file.',
    ),
    'files.code': ('Kode {code}', 'Code {code}'),
    'files.searchHint': ('Cari nama berkas...', 'Search file name...'),
    'files.emptyTitle': ('Belum ada transfer', 'No transfers yet'),
    'files.emptySearch': ('Tidak ada berkas', 'No files found'),
    'files.emptyMessage': (
      'Pilih file lewat tombol di atas. File yang diterima bisa langsung dibuka dari sini.',
      'Pick a file using the button above. Received files can be opened from here.',
    ),
    'files.searchMessage': (
      'Coba kata kunci lain atau ubah filter.',
      'Try another keyword or change the filter.',
    ),
    'files.pickFile': ('Pilih File', 'Pick File'),
    'files.sendFile': ('Kirim Berkas', 'Send File'),
    'files.active': ('Transfer Aktif', 'Active Transfers'),
    'files.wifiSpeed': ('Kecepatan WiFi', 'WiFi Speed'),
    'files.receivedTotal': ('Total Diterima', 'Total Received'),
    'files.running': ('berjalan', 'running'),
    'files.received': ('Data Diterima', 'Data Received'),
    'files.storage': ('Penyimpanan', 'Storage'),
    'files.free': ('bebas', 'free'),
    'files.ofTotal': ('dari {size}', 'of {size}'),
    'files.unavailable': ('Tidak tersedia', 'Unavailable'),
    'files.filesCount': ('{count} file', '{count} files'),
    'files.all': ('Semua', 'All'),
    'files.incoming': ('Masuk', 'Incoming'),
    'files.outgoing': ('Keluar', 'Outgoing'),
    'files.failedMeta': ('Gagal • {size}', 'Failed • {size}'),
    'files.to': ('Ke', 'To'),
    'files.from': ('Dari', 'From'),
    'files.open': ('Buka', 'Open'),
    'files.failed': ('Gagal', 'Failed'),
    'files.processing': ('Proses', 'Processing'),
    'notes.title': ('Catatan', 'Notes'),
    'notes.count': ('{count} catatan', '{count} notes'),
    'notes.favoriteCount': ('{count} favorit', '{count} favorites'),
    'notes.localTitle': ('Penyimpanan Lokal', 'Local Storage'),
    'notes.localMessage': (
      'Catatan disimpan di perangkat ini, tanpa sinkronisasi',
      'Notes are stored on this device without sync',
    ),
    'notes.offline': ('Offline', 'Offline'),
    'notes.noCloud': ('Tanpa cloud', 'No cloud'),
    'notes.savedLocal': ('Tersimpan lokal', 'Saved locally'),
    'notes.deviceThis': ('Perangkat Ini', 'This Device'),
    'notes.searchHint': (
      'Cari judul atau isi catatan...',
      'Search note title or content...',
    ),
    'notes.add': ('Catatan', 'Note'),
    'notes.emptyTitle': ('Belum ada catatan', 'No notes yet'),
    'notes.noResults': ('Tidak ada hasil', 'No results'),
    'notes.emptyMessage': (
      'Mulai catatan pertama. Semua tersimpan offline di perangkat ini.',
      'Start your first note. Everything is stored offline on this device.',
    ),
    'notes.searchMessage': (
      'Coba kata kunci lain atau ubah filter.',
      'Try another keyword or change the filter.',
    ),
    'notes.create': ('Buat Catatan', 'Create Note'),
    'notes.all': ('Semua', 'All'),
    'notes.favorite': ('Favorit', 'Favorites'),
    'notes.untitled': ('Tanpa judul', 'Untitled'),
    'notes.emptyPreview': (
      'Catatan kosong. Ketuk untuk mulai menulis.',
      'Empty note. Tap to start writing.',
    ),
    'notes.copyTooltip': ('Salin catatan', 'Copy note'),
    'notes.copied': ('Catatan disalin', 'Note copied'),
    'notes.deleteTitle': ('Hapus catatan?', 'Delete note?'),
    'notes.untitledNote': ('Catatan tanpa judul', 'Untitled note'),
    'notes.cancel': ('Batal', 'Cancel'),
    'notes.delete': ('Hapus', 'Delete'),
    'editor.new': ('Catatan Baru', 'New Note'),
    'editor.edit': ('Sunting Catatan', 'Edit Note'),
    'editor.saved': ('Tersimpan', 'Saved'),
    'editor.save': ('Simpan', 'Save'),
    'editor.titleHint': ('Judul catatan', 'Note title'),
    'editor.contentHint': (
      'Mulai menulis. Perubahan tersimpan otomatis.',
      'Start writing. Changes are saved automatically.',
    ),
    'editor.bold': ('Tebal', 'Bold'),
    'editor.italic': ('Miring', 'Italic'),
    'editor.code': ('Kode', 'Code'),
    'editor.heading': ('Judul', 'Heading'),
    'editor.list': ('Daftar', 'List'),
    'editor.checklist': ('Checklist', 'Checklist'),
    'editor.quote': ('Kutipan', 'Quote'),
    'editor.placeholder': ('teks', 'text'),
    'editor.favoriteOn': ('Hapus dari favorit', 'Remove from favorites'),
    'editor.favoriteOff': ('Tandai favorit', 'Mark as favorite'),
    'qr.title': ('Pindai QR Drople', 'Scan Drople QR'),
    'qr.cameraError': ('Kamera tidak dapat digunakan', 'Camera unavailable'),
    'qr.cameraHint': (
      'Gunakan kode manual dari layar sebelumnya.',
      'Use the manual code from the previous screen.',
    ),
    'home.networkWarning': (
      'Jaringan P2P belum aktif. Catatan tetap bisa dipakai offline.',
      'P2P network is not active. Notes still work offline.',
    ),
    'home.coreError': ('Core gagal dimuat', 'Failed to load core'),
    'home.retry': ('Coba Lagi', 'Try Again'),
    'home.preparing': ('Menyiapkan ruang kerjamu', 'Preparing your workspace'),
    'home.backupTitle': ('Backup segera hadir', 'Backup coming soon'),
    'home.backupMessage': (
      'Fitur backup cloud masih dalam pengembangan. Catatanmu tetap tersimpan aman di perangkat ini.',
      'Cloud backup is still in development. Your notes remain safely stored on this device.',
    ),
    'home.gotIt': ('Mengerti', 'Got it'),
    'common.justNow': ('baru saja', 'just now'),
    'common.minutesAgo': ('{count} menit lalu', '{count} min ago'),
    'common.hoursAgo': ('{count} jam lalu', '{count} h ago'),
    'common.daysAgo': ('{count} hari lalu', '{count} d ago'),
  };
}

extension L10nContext on BuildContext {
  L10n get l10n => L10n.of(this);
}
