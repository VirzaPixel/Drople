use std::ffi::{CStr, CString, c_char, c_int};

use crate::backup;
use crate::error::{DropleError, Result};
use crate::{db, sync, with_conn};

fn cstr_to_string(ptr: *const c_char) -> Result<String> {
    if ptr.is_null() {
        return Err(DropleError::InvalidInput("null pointer".into()));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| DropleError::InvalidInput("invalid utf-8".into()))
}

fn write_out(out: *mut *mut c_char, value: String) -> Result<()> {
    if out.is_null() {
        return Err(DropleError::InvalidInput("output pointer null".into()));
    }
    let ptr = CString::new(value)
        .map_err(|_| DropleError::InvalidInput("string mengandung NUL".into()))?
        .into_raw();
    unsafe { *out = ptr }
    Ok(())
}

fn write_bool(out: *mut c_int, value: bool) -> Result<()> {
    if out.is_null() {
        return Err(DropleError::InvalidInput("output pointer null".into()));
    }
    unsafe { *out = if value { 1 } else { 0 } }
    Ok(())
}

fn run(f: impl FnOnce() -> Result<()>) -> c_int {
    match f() {
        Ok(()) => 0,
        Err(e) => e.code(),
    }
}

/// Inisialisasi core. `db_path` adalah path file SQLite (atau ":memory:").
#[unsafe(no_mangle)]
pub extern "C" fn drople_init(db_path: *const c_char) -> c_int {
    let path = match cstr_to_string(db_path) {
        Ok(p) => p,
        Err(e) => return e.code(),
    };
    match crate::init(&path) {
        Ok(()) => 0,
        Err(e) => e.code(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_cleanup() {
    crate::cleanup();
}

/// Membebaskan string yang dialokasikan oleh Rust.
#[unsafe(no_mangle)]
pub extern "C" fn drople_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

// ---------------------------------------------------------------------------
// Notes
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_create(
    title: *const c_char,
    content: *const c_char,
    out_id: *mut *mut c_char,
) -> c_int {
    let title = match cstr_to_string(title) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let content = match cstr_to_string(content) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        let id = with_conn(|conn| db::create_note(conn, &title, &content))?;
        write_out(out_id, id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_get(
    id: *const c_char,
    out_title: *mut *mut c_char,
    out_content: *mut *mut c_char,
) -> c_int {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        let note = with_conn(|conn| db::get_note(conn, &id))?;
        write_out(out_title, note.title)?;
        write_out(out_content, note.content)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_update(
    id: *const c_char,
    title: *const c_char,
    content: *const c_char,
) -> c_int {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let title = match cstr_to_string(title) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let content = match cstr_to_string(content) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| with_conn(|conn| db::update_note(conn, &id, &title, &content)))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_delete(id: *const c_char) -> c_int {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| with_conn(|conn| db::delete_note(conn, &id)))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_set_favorite(id: *const c_char, favorite: c_int) -> c_int {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| with_conn(|conn| db::set_note_favorite(conn, &id, favorite != 0)))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_list(out_json: *mut *mut c_char) -> c_int {
    run(|| {
        let json = with_conn(|conn| {
            let notes = db::list_notes(conn)?;
            Ok(serde_json::to_string(&notes)?)
        })?;
        write_out(out_json, json)
    })
}

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_sync_status(
    id: *const c_char,
    out_status: *mut *mut c_char,
) -> c_int {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        let status = sync::sync_status(&id)?;
        write_out(out_status, status)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_pending_list(out_json: *mut *mut c_char) -> c_int {
    run(|| {
        let json = sync::pending_list()?;
        write_out(out_json, json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_apply_delta(
    delta_json: *const c_char,
    local_peer_id: *const c_char,
) -> c_int {
    let delta_json = match cstr_to_string(delta_json) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let local_peer_id = match cstr_to_string(local_peer_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| sync::apply_delta_json(&delta_json, &local_peer_id))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_mark_all_synced() -> c_int {
    run(sync::mark_all_synced)
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_note_sync_with_peer(peer_id: *const c_char) -> c_int {
    let peer_id = match cstr_to_string(peer_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| crate::net::sync_with_peer(&peer_id))
}

// ---------------------------------------------------------------------------
// Network & pairing
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn drople_network_start() -> c_int {
    run(crate::net::start)
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_network_stop() -> c_int {
    crate::net::stop();
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_set_device_name(name: *const c_char) -> c_int {
    let name = match cstr_to_string(name) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| crate::net::set_device_name(&name))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_local_short_code(out_code: *mut *mut c_char) -> c_int {
    run(|| {
        let code = crate::net::local_short_code()?;
        write_out(out_code, code)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_local_peer_id(out_peer_id: *mut *mut c_char) -> c_int {
    run(|| {
        let id = crate::net::local_peer_id()?;
        write_out(out_peer_id, id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_local_fingerprint(out_fingerprint: *mut *mut c_char) -> c_int {
    run(|| {
        let fingerprint = crate::net::local_fingerprint()?;
        write_out(out_fingerprint, fingerprint)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_peers_list(out_json: *mut *mut c_char) -> c_int {
    run(|| {
        let json = crate::net::peers_json()?;
        write_out(out_json, json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_pairing_start(out_code: *mut *mut c_char) -> c_int {
    run(|| {
        let code = crate::net::pairing_start()?;
        write_out(out_code, code)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_pairing_connect(code: *const c_char) -> c_int {
    let code = match cstr_to_string(code) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| crate::net::pairing_connect(&code))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_network_add_relay(addr: *const c_char) -> c_int {
    let addr = match cstr_to_string(addr) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| crate::net::add_relay(&addr))
}

// ---------------------------------------------------------------------------
// File transfer
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn drople_file_send(
    peer_id: *const c_char,
    file_path: *const c_char,
    out_transfer_id: *mut *mut c_char,
) -> c_int {
    let peer_id = match cstr_to_string(peer_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let file_path = match cstr_to_string(file_path) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        let id = crate::file::file_send(&peer_id, &file_path)?;
        write_out(out_transfer_id, id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_file_receive(
    peer_id: *const c_char,
    save_path: *const c_char,
    out_transfer_id: *mut *mut c_char,
) -> c_int {
    let peer_id = match cstr_to_string(peer_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let save_path = match cstr_to_string(save_path) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        let id = crate::file::file_receive(&peer_id, &save_path)?;
        write_out(out_transfer_id, id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_file_set_receive_dir(path: *const c_char) -> c_int {
    let path = match cstr_to_string(path) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| crate::net::set_receive_dir(&path))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_file_list(out_json: *mut *mut c_char) -> c_int {
    run(|| {
        let json = crate::file::file_list()?;
        write_out(out_json, json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_file_transfer_status(
    id: *const c_char,
    out_status: *mut *mut c_char,
) -> c_int {
    let id = match cstr_to_string(id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        let status = crate::file::file_transfer_status(&id)?;
        write_out(out_status, status)
    })
}

// ---------------------------------------------------------------------------
// Google Drive backup
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_set_token(
    access_token: *const c_char,
    refresh_token: *const c_char,
    expires_at: i64,
) -> c_int {
    let access_token = match cstr_to_string(access_token) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let refresh_token = match cstr_to_string(refresh_token) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| backup::gdrive::set_token(&access_token, &refresh_token, expires_at))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_is_connected(out_connected: *mut c_int) -> c_int {
    run(|| {
        let connected = backup::gdrive::is_connected()?;
        write_bool(out_connected, connected)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_backup(out_backup_id: *mut *mut c_char) -> c_int {
    run(|| {
        let id = backup::backup_now()?;
        write_out(out_backup_id, id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_backup_list(out_json: *mut *mut c_char) -> c_int {
    run(|| {
        let json = backup::list_backups()?;
        write_out(out_json, json)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_restore(backup_id: *const c_char) -> c_int {
    let backup_id = match cstr_to_string(backup_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| backup::restore_backup(&backup_id))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_delete(backup_id: *const c_char) -> c_int {
    let backup_id = match cstr_to_string(backup_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| backup::delete_backup(&backup_id))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_disconnect() -> c_int {
    run(backup::disconnect)
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_backup_recovery_key(out_mnemonic: *mut *mut c_char) -> c_int {
    run(|| {
        let key = backup::get_or_create_recovery_key()?;
        write_out(out_mnemonic, key)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_backup_set_recovery_key(mnemonic: *const c_char) -> c_int {
    let mnemonic = match cstr_to_string(mnemonic) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| backup::set_recovery_key(&mnemonic))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_backup_is_configured(out_configured: *mut c_int) -> c_int {
    run(|| {
        let configured = backup::is_configured()?;
        write_bool(out_configured, configured)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_client_id(out_client_id: *mut *mut c_char) -> c_int {
    run(|| {
        let client_id = backup::gdrive::configured_client_id()?;
        write_out(out_client_id, client_id)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_has_client_secret(out_configured: *mut c_int) -> c_int {
    run(|| {
        let configured = backup::gdrive::has_client_secret()?;
        write_bool(out_configured, configured)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_exchange_code(
    code: *const c_char,
    verifier: *const c_char,
    redirect_uri: *const c_char,
) -> c_int {
    let code = match cstr_to_string(code) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let verifier = match cstr_to_string(verifier) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let redirect_uri = match cstr_to_string(redirect_uri) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| backup::gdrive::exchange_code(&code, &verifier, &redirect_uri))
}

#[unsafe(no_mangle)]
pub extern "C" fn drople_gdrive_set_client(
    client_id: *const c_char,
    client_secret: *const c_char,
) -> c_int {
    let client_id = match cstr_to_string(client_id) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    let client_secret = match cstr_to_string(client_secret) {
        Ok(v) => v,
        Err(e) => return e.code(),
    };
    run(|| {
        with_conn(|conn| {
            db::set_setting(conn, backup::gdrive::KEY_CLIENT_ID, &client_id)?;
            if !client_secret.trim().is_empty() {
                db::set_setting(conn, backup::gdrive::KEY_CLIENT_SECRET, &client_secret)?;
            }
            Ok(())
        })
    })
}
