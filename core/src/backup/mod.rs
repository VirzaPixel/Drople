pub mod gdrive;
pub mod snapshot;

use serde::Serialize;

use crate::crypto::sha256_hex;
use crate::db;
use crate::error::{DropleError, Result};
use crate::sync;
use crate::sync::protocol::NoteDelta;
use crate::with_conn;

pub const KEY_RECOVERY: &str = "backup_recovery_key";

#[derive(Debug, Clone, Serialize)]
pub struct BackupInfo {
    pub id: String,
    pub created_at: i64,
    pub size: i64,
    pub status: String,
    pub local_checksum: Option<String>,
}

/// Mengambil recovery key yang tersimpan, atau membuat baru bila belum ada.
pub fn get_or_create_recovery_key() -> Result<String> {
    with_conn(get_or_create_recovery_key_on)
}

pub fn get_or_create_recovery_key_on(conn: &rusqlite::Connection) -> Result<String> {
    let existing = db::get_setting(conn, KEY_RECOVERY)?;
    if let Some(key) = existing.filter(|k| !k.trim().is_empty()) {
        snapshot::validate_recovery_key(&key)?;
        return Ok(key);
    }
    let key = snapshot::generate_recovery_key();
    db::set_setting(conn, KEY_RECOVERY, &key)?;
    Ok(key)
}

pub fn set_recovery_key(mnemonic: &str) -> Result<()> {
    let normalized = mnemonic
        .split_whitespace()
        .map(|w| w.to_ascii_lowercase())
        .collect::<Vec<_>>()
        .join(" ");
    snapshot::validate_recovery_key(&normalized)?;
    with_conn(|conn| db::set_setting(conn, KEY_RECOVERY, &normalized))
}

pub fn recovery_key() -> Result<String> {
    with_conn(|conn| db::get_setting(conn, KEY_RECOVERY))?
        .filter(|k| !k.trim().is_empty())
        .ok_or(DropleError::RecoveryKeyMissing)
}

pub fn is_configured() -> Result<bool> {
    let key = with_conn(|conn| db::get_setting(conn, KEY_RECOVERY))?;
    Ok(key.map(|k| !k.trim().is_empty()).unwrap_or(false))
}

/// Membuat snapshot terenkripsi dari seluruh catatan dan mengunggahnya ke Drive.
pub fn backup_now() -> Result<String> {
    let mnemonic = recovery_key()?;
    let notes = with_conn(|conn| db::list_notes_for_sync(conn))?;
    let snapshot = snapshot::Snapshot::from_notes(notes);
    let blob = snapshot::encrypt_snapshot(&snapshot, &mnemonic)?;
    let checksum = sha256_hex(&blob);
    let created_at = db::now_millis();
    let file_name = gdrive::backup_file_name(created_at);

    with_conn(|conn| {
        db::upsert_backup(
            conn,
            &file_name,
            created_at,
            blob.len() as i64,
            "uploading",
            Some(&checksum),
        )
    })?;

    let remote_id = match gdrive::upload(&file_name, blob.clone()) {
        Ok(id) => id,
        Err(e) => {
            let _ = with_conn(|conn| db::update_backup_status(conn, &file_name, "failed"));
            return Err(e);
        }
    };

    with_conn(|conn| {
        db::delete_backup(conn, &file_name)?;
        db::upsert_backup(
            conn,
            &remote_id,
            created_at,
            blob.len() as i64,
            "completed",
            Some(&checksum),
        )
    })?;

    Ok(remote_id)
}

pub fn list_backups() -> Result<String> {
    let remote = gdrive::list().unwrap_or_default();
    let local = with_conn(|conn| db::list_backups(conn))?;

    let infos: Vec<BackupInfo> = remote
        .into_iter()
        .map(|r| {
            let local_entry = local.iter().find(|b| b.id == r.id);
            BackupInfo {
                id: r.id,
                created_at: if r.created_at > 0 {
                    r.created_at
                } else {
                    local_entry.map(|b| b.created_at).unwrap_or(0)
                },
                size: if r.size > 0 {
                    r.size
                } else {
                    local_entry.map(|b| b.size).unwrap_or(0)
                },
                status: local_entry
                    .map(|b| b.status.clone())
                    .unwrap_or_else(|| "completed".to_string()),
                local_checksum: local_entry.and_then(|b| b.local_checksum.clone()),
            }
        })
        .collect();

    Ok(serde_json::to_string(&infos)?)
}

/// Mengunduh, mendekripsi, lalu merge catatan backup ke database lokal.
pub fn restore_backup(backup_id: &str) -> Result<()> {
    let mnemonic = recovery_key()?;
    let blob = gdrive::download(backup_id)?;
    let snapshot = snapshot::decrypt_snapshot(&blob, &mnemonic)?;
    let local_peer = crate::net::local_peer_id().unwrap_or_else(|_| "restore".to_string());

    with_conn(|conn| {
        for note in &snapshot.notes {
            let delta = NoteDelta {
                id: note.id.clone(),
                title: note.title.clone(),
                content: note.content.clone(),
                vector_clock: note.vector_clock.clone(),
                deleted: note.deleted_at.is_some(),
                deleted_at: note.deleted_at,
                source_peer_id: note
                    .source_peer_id
                    .clone()
                    .unwrap_or_else(|| "backup".to_string()),
                updated_at: note.updated_at,
                version: note.version,
                created_at: note.created_at,
            };
            sync::apply_delta_on(conn, &delta, &local_peer)?;
        }
        Ok(())
    })
}

pub fn delete_backup(backup_id: &str) -> Result<()> {
    gdrive::delete(backup_id)?;
    with_conn(|conn| db::delete_backup(conn, backup_id))
}

pub fn disconnect() -> Result<()> {
    gdrive::disconnect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn recovery_key_is_created_and_persisted() {
        let conn = Connection::open_in_memory().unwrap();
        db::init_schema(&conn).unwrap();
        let first = get_or_create_recovery_key_on(&conn).unwrap();
        let second = get_or_create_recovery_key_on(&conn).unwrap();
        assert_eq!(first, second);
        snapshot::validate_recovery_key(&first).unwrap();
    }

    #[test]
    fn restore_merges_snapshot_into_database() {
        let conn = Connection::open_in_memory().unwrap();
        db::init_schema(&conn).unwrap();

        let mnemonic = snapshot::generate_recovery_key();
        let note = db::Note {
            id: "n1".into(),
            title: "Backup".into(),
            content: "Isi".into(),
            created_at: 1,
            updated_at: 2,
            version: 1,
            is_favorite: 0,
            deleted_at: None,
            vector_clock: "{}".into(),
            source_peer_id: Some("p".into()),
            sync_status: "synced".into(),
        };
        let blob =
            snapshot::encrypt_snapshot(&snapshot::Snapshot::from_notes(vec![note]), &mnemonic)
                .unwrap();
        let restored = snapshot::decrypt_snapshot(&blob, &mnemonic).unwrap();

        for n in &restored.notes {
            let delta = NoteDelta {
                id: n.id.clone(),
                title: n.title.clone(),
                content: n.content.clone(),
                vector_clock: n.vector_clock.clone(),
                deleted: n.deleted_at.is_some(),
                deleted_at: n.deleted_at,
                source_peer_id: n.source_peer_id.clone().unwrap_or_default(),
                updated_at: n.updated_at,
                version: n.version,
                created_at: n.created_at,
            };
            sync::apply_delta_on(&conn, &delta, "local").unwrap();
        }

        let note = db::get_note(&conn, "n1").unwrap();
        assert_eq!(note.title, "Backup");
    }
}
