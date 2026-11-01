// ignore_for_file: avoid_print
// Smoke test FFI langsung ke `drople_core`.
//
// Jalankan dengan:
//   DROPLE_CORE_LIB=<abs path libdrople_core.so> dart run tool/ffi_smoke.dart
import 'package:drople/ffi/drople_bindings.dart';

void main() {
  final b = DropleBindings.instance;

  final rc = b.init(':memory:');
  if (rc != 0) {
    throw StateError('init gagal: $rc');
  }

  final id = b.noteCreate('Catatan Pertama', 'Halo dari Rust!');
  print('created: $id');

  final fetched = b.noteGet(id);
  print('get: title=${fetched.title} content=${fetched.content}');

  b.noteUpdate(id, 'Catatan Diubah', 'Isi baru');
  final updated = b.noteGet(id);
  print('updated: ${updated.title} / ${updated.content}');

  print('list: ${b.noteListJson()}');

  b.noteDelete(id);
  print('after delete list: ${b.noteListJson()}');

  b.cleanup();
  print('SMOKE OK');
}
