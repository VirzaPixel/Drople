pub mod crdt;
pub mod protocol;

use serde::{Deserialize, Serialize};

use crate::db;
use crate::error::{DropleError, Result};
use crate::sync::protocol::NoteDelta;
use crate::with_conn;

/// Status sinkronisasi catatan.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum SyncStatus {
    Synced,
    Pending,
    Conflict,
}

impl std::fmt::Display for SyncStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncStatus::Synced => write!(f, "synced"),
            SyncStatus::Pending => write!(f, "pending"),
            SyncStatus::Conflict => write!(f, "conflict"),
        }
    }
}

/// Memeriksa status sinkronisasi sebuah catatan.
pub fn sync_status(note_id: &str) -> Result<String> {
    with_conn(|conn| db::get_note_sync_status(conn, note_id))
}

/// Dapatkan daftar catatan yang perlu disinkronkan.
pub fn pending_list() -> Result<String> {
    with_conn(|conn| {
        let notes = db::get_pending_notes(conn)?;
        Ok(serde_json::to_string(&notes)?)
    })
}

/// Semua delta catatan lokal (termasuk tombstone) untuk dikirim ke peer.
pub fn local_deltas() -> Result<Vec<NoteDelta>> {
    with_conn(|conn| {
        let notes = db::list_notes_for_sync(conn)?;
        Ok(notes.iter().map(NoteDelta::from_note).collect())
    })
}

/// Tandai semua catatan pending sebagai synced.
pub fn mark_all_synced() -> Result<()> {
    with_conn(|conn| {
        let pending = db::get_pending_notes(conn)?;
        for note in pending {
            let note = db::get_note_any(conn, &note.id)?;
            db::mark_note_synced(conn, &note.id, &note.vector_clock, note.source_peer_id.as_deref())?;
        }
        Ok(())
    })
}

/// Terima delta catatan dari peer dan merge ke database lokal.
pub fn apply_delta(delta: &NoteDelta, local_peer_id: &str) -> Result<()> {
    with_conn(|conn| apply_delta_on(conn, delta, local_peer_id))
}

pub fn apply_delta_on(
    conn: &rusqlite::Connection,
    delta: &NoteDelta,
    local_peer_id: &str,
) -> Result<()> {
    let existing = db::get_note_any(conn, &delta.id).ok();

    let merged = match &existing {
        Some(local_note) => {
            let local_crdt = crdt::NoteCRDT::from_db_note(local_note);
            let remote_crdt = crdt::NoteCRDT::from_delta(delta);
            crdt::merge_notes(&local_crdt, &remote_crdt, local_peer_id)
        }
        None => crdt::NoteCRDT::from_delta(delta),
    };

    let created_at = match &existing {
        Some(existing) => existing.created_at,
        None => {
            if delta.created_at > 0 {
                delta.created_at
            } else {
                delta.updated_at
            }
        }
    };

    db::upsert_note_from_sync(
        conn,
        &merged.id,
        &merged.title.value,
        &merged.content.value,
        &merged.vector_clock_json(),
        &merged.source_peer_id,
        merged.latest_timestamp(),
        merged.version,
        merged.deleted_at,
        created_at,
    )
}

/// Terapkan delta dari JSON (dipakai FFI).
pub fn apply_delta_json(delta_json: &str, local_peer_id: &str) -> Result<()> {
    let delta = NoteDelta::from_json(delta_json)
        .map_err(|e| DropleError::InvalidInput(format!("delta JSON tidak valid: {e}")))?;
    apply_delta(&delta, local_peer_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db;
    use rusqlite::Connection;

    fn setup() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        db::init_schema(&conn).unwrap();
        conn
    }

    fn delta(id: &str, title: &str, ts: i64) -> NoteDelta {
        NoteDelta {
            id: id.into(),
            title: title.into(),
            content: "body".into(),
            vector_clock: "{\"p\":1}".into(),
            deleted: false,
            deleted_at: None,
            source_peer_id: "p".into(),
            updated_at: ts,
            version: 1,
            created_at: ts,
        }
    }

    #[test]
    fn apply_delta_inserts_new_note() {
        let conn = setup();
        apply_delta_on(&conn, &delta("n1", "Remote", 100), "local").unwrap();
        let note = db::get_note(&conn, "n1").unwrap();
        assert_eq!(note.title, "Remote");
        assert_eq!(note.sync_status, "synced");
    }

    #[test]
    fn apply_delta_keeps_newer_local() {
        let conn = setup();
        let id = db::create_note(&conn, "Lokal", "isi").unwrap();
        db::update_note(&conn, &id, "Lokal", "isi").unwrap();
        db::mark_note_synced(&conn, &id, "{}", Some("local")).unwrap();
        let mut remote = delta(&id, "Remote", 1);
        remote.updated_at = 1;
        apply_delta_on(&conn, &remote, "local").unwrap();
        let note = db::get_note(&conn, &id).unwrap();
        assert_eq!(note.title, "Lokal");
    }
}
