use rusqlite::{Connection, OptionalExtension, params};
use serde::Serialize;

use crate::error::{DropleError, Result};

pub const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS notes (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    deleted_at INTEGER DEFAULT NULL,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    vector_clock TEXT NOT NULL DEFAULT '{}',
    source_peer_id TEXT DEFAULT NULL,
    sync_status TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS file_transfers (
    id TEXT PRIMARY KEY,
    peer_id TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    file_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    direction TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    completed_at INTEGER DEFAULT NULL,
    local_path TEXT DEFAULT NULL,
    progress INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS peers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    public_key TEXT NOT NULL,
    last_seen INTEGER DEFAULT NULL,
    paired_at INTEGER NOT NULL,
    fingerprint TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS backups (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    size INTEGER NOT NULL,
    status TEXT NOT NULL,
    local_checksum TEXT DEFAULT NULL
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);
CREATE INDEX IF NOT EXISTS idx_file_transfers_status ON file_transfers(status);
CREATE INDEX IF NOT EXISTS idx_peers_last_seen ON peers(last_seen);
CREATE INDEX IF NOT EXISTS idx_backups_created_at ON backups(created_at);
"#;

#[derive(Debug, Serialize, Clone)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub content: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub version: i64,
    pub is_favorite: i64,
    pub deleted_at: Option<i64>,
    pub vector_clock: String,
    pub source_peer_id: Option<String>,
    pub sync_status: String,
}

#[derive(Debug, Serialize, Clone)]
pub struct NoteSummary {
    pub id: String,
    pub title: String,
    pub updated_at: i64,
    pub is_favorite: i64,
    pub sync_status: String,
}

#[derive(Debug, Serialize, Clone)]
pub struct FileTransferView {
    pub id: String,
    pub peer_id: String,
    pub file_name: String,
    pub file_size: i64,
    pub file_hash: String,
    pub status: String,
    pub direction: String,
    pub created_at: i64,
    pub completed_at: Option<i64>,
    pub local_path: Option<String>,
    pub progress: i64,
}

#[derive(Debug, Serialize, Clone)]
pub struct BackupView {
    pub id: String,
    pub created_at: i64,
    pub size: i64,
    pub status: String,
    pub local_checksum: Option<String>,
}

pub fn now_millis() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn column_exists(conn: &Connection, table: &str, column: &str) -> Result<bool> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        let name: String = row.get(1)?;
        if name == column {
            return Ok(true);
        }
    }
    Ok(false)
}

fn add_column_if_missing(
    conn: &Connection,
    table: &str,
    column: &str,
    definition: &str,
) -> Result<()> {
    if !column_exists(conn, table, column)? {
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {definition}"),
            [],
        )?;
    }
    Ok(())
}

pub fn init_schema(conn: &Connection) -> Result<()> {
    conn.execute_batch(SCHEMA)?;

    // Migrasi database dari versi fase sebelumnya.
    add_column_if_missing(conn, "notes", "vector_clock", "TEXT NOT NULL DEFAULT '{}'")?;
    add_column_if_missing(conn, "notes", "source_peer_id", "TEXT DEFAULT NULL")?;
    add_column_if_missing(
        conn,
        "notes",
        "sync_status",
        "TEXT NOT NULL DEFAULT 'pending'",
    )?;
    add_column_if_missing(
        conn,
        "file_transfers",
        "progress",
        "INTEGER NOT NULL DEFAULT 0",
    )?;
    add_column_if_missing(conn, "peers", "fingerprint", "TEXT NOT NULL DEFAULT ''")?;
    Ok(())
}

fn map_note(row: &rusqlite::Row<'_>) -> rusqlite::Result<Note> {
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        content: row.get(2)?,
        created_at: row.get(3)?,
        updated_at: row.get(4)?,
        version: row.get(5)?,
        is_favorite: row.get(6)?,
        deleted_at: row.get(7)?,
        vector_clock: row.get(8)?,
        source_peer_id: row.get(9)?,
        sync_status: row.get(10)?,
    })
}

fn map_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<NoteSummary> {
    Ok(NoteSummary {
        id: row.get(0)?,
        title: row.get(1)?,
        updated_at: row.get(2)?,
        is_favorite: row.get(3)?,
        sync_status: row.get(4)?,
    })
}

pub fn create_note(conn: &Connection, title: &str, content: &str) -> Result<String> {
    let id = uuid::Uuid::new_v4().to_string();
    let now = now_millis();
    conn.execute(
        "INSERT INTO notes (id, title, content, created_at, updated_at, version, is_favorite, vector_clock, source_peer_id, sync_status)
         VALUES (?1, ?2, ?3, ?4, ?4, 1, 0, '{}', NULL, 'pending')",
        params![id, title, content, now],
    )?;
    Ok(id)
}

pub fn get_note(conn: &Connection, id: &str) -> Result<Note> {
    let note = conn
        .query_row(
            "SELECT id, title, content, created_at, updated_at, version, is_favorite,
                    deleted_at, vector_clock, source_peer_id, sync_status
             FROM notes WHERE id = ?1 AND deleted_at IS NULL",
            params![id],
            map_note,
        )
        .optional()?;
    note.ok_or(DropleError::NotFound)
}

pub fn get_note_any(conn: &Connection, id: &str) -> Result<Note> {
    let note = conn
        .query_row(
            "SELECT id, title, content, created_at, updated_at, version, is_favorite,
                    deleted_at, vector_clock, source_peer_id, sync_status
             FROM notes WHERE id = ?1",
            params![id],
            map_note,
        )
        .optional()?;
    note.ok_or(DropleError::NotFound)
}

pub fn update_note(conn: &Connection, id: &str, title: &str, content: &str) -> Result<()> {
    let now = now_millis();
    let affected = conn.execute(
        "UPDATE notes
         SET title = ?2, content = ?3, updated_at = ?4, version = version + 1,
             sync_status = 'pending'
         WHERE id = ?1 AND deleted_at IS NULL",
        params![id, title, content, now],
    )?;
    if affected == 0 {
        return Err(DropleError::NotFound);
    }
    Ok(())
}

pub fn delete_note(conn: &Connection, id: &str) -> Result<()> {
    let now = now_millis();
    let affected = conn.execute(
        "UPDATE notes
         SET deleted_at = ?2, updated_at = ?2, version = version + 1,
             sync_status = 'pending'
         WHERE id = ?1 AND deleted_at IS NULL",
        params![id, now],
    )?;
    if affected == 0 {
        return Err(DropleError::NotFound);
    }
    Ok(())
}

pub fn list_notes(conn: &Connection) -> Result<Vec<NoteSummary>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, updated_at, is_favorite, sync_status
         FROM notes WHERE deleted_at IS NULL
         ORDER BY is_favorite DESC, updated_at DESC",
    )?;
    let rows = stmt.query_map([], map_summary)?;
    let mut notes = Vec::new();
    for row in rows {
        notes.push(row?);
    }
    Ok(notes)
}

pub fn list_notes_for_sync(conn: &Connection) -> Result<Vec<Note>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, content, created_at, updated_at, version, is_favorite,
                deleted_at, vector_clock, source_peer_id, sync_status
         FROM notes ORDER BY updated_at ASC",
    )?;
    let rows = stmt.query_map([], map_note)?;
    let mut notes = Vec::new();
    for row in rows {
        notes.push(row?);
    }
    Ok(notes)
}

pub fn get_setting(conn: &Connection, key: &str) -> Result<Option<String>> {
    Ok(conn
        .query_row(
            "SELECT value FROM settings WHERE key = ?1",
            params![key],
            |row| row.get::<_, String>(0),
        )
        .optional()?)
}

pub fn set_setting(conn: &Connection, key: &str, value: &str) -> Result<()> {
    conn.execute(
        "INSERT INTO settings (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

pub fn delete_setting(conn: &Connection, key: &str) -> Result<()> {
    conn.execute("DELETE FROM settings WHERE key = ?1", params![key])?;
    Ok(())
}

pub fn upsert_peer(
    conn: &Connection,
    id: &str,
    name: &str,
    public_key: &str,
    fingerprint: &str,
) -> Result<()> {
    let now = now_millis();
    conn.execute(
        "INSERT INTO peers (id, name, public_key, last_seen, paired_at, fingerprint)
         VALUES (?1, ?2, ?3, ?4, ?4, ?5)
         ON CONFLICT(id) DO UPDATE SET
             name = excluded.name,
             public_key = excluded.public_key,
             last_seen = excluded.last_seen,
             fingerprint = excluded.fingerprint",
        params![id, name, public_key, now, fingerprint],
    )?;
    Ok(())
}

pub fn get_peer_fingerprint(conn: &Connection, id: &str) -> Result<Option<String>> {
    Ok(conn
        .query_row(
            "SELECT fingerprint FROM peers WHERE id = ?1",
            params![id],
            |row| row.get::<_, String>(0),
        )
        .optional()?)
}

pub fn mark_note_synced(
    conn: &Connection,
    id: &str,
    vector_clock: &str,
    source_peer_id: Option<&str>,
) -> Result<()> {
    conn.execute(
        "UPDATE notes
         SET sync_status = 'synced', vector_clock = ?2, source_peer_id = COALESCE(?3, source_peer_id)
         WHERE id = ?1",
        params![id, vector_clock, source_peer_id],
    )?;
    Ok(())
}

pub fn get_pending_notes(conn: &Connection) -> Result<Vec<NoteSummary>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, updated_at, is_favorite, sync_status
         FROM notes WHERE sync_status != 'synced'
         ORDER BY updated_at ASC",
    )?;
    let rows = stmt.query_map([], map_summary)?;
    let mut notes = Vec::new();
    for row in rows {
        notes.push(row?);
    }
    Ok(notes)
}

/// Insert catatan baru atau update catatan yang sudah ada dari hasil sinkronisasi.
pub fn upsert_note_from_sync(
    conn: &Connection,
    id: &str,
    title: &str,
    content: &str,
    vector_clock: &str,
    source_peer_id: &str,
    updated_at: i64,
    version: i64,
    deleted_at: Option<i64>,
    created_at: i64,
) -> Result<()> {
    let created = if created_at > 0 { created_at } else { updated_at };
    conn.execute(
        "INSERT INTO notes
            (id, title, content, created_at, updated_at, version, is_favorite,
             deleted_at, vector_clock, source_peer_id, sync_status)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, ?7, ?8, ?9, 'synced')
         ON CONFLICT(id) DO UPDATE SET
             title = excluded.title,
             content = excluded.content,
             updated_at = excluded.updated_at,
             version = excluded.version,
             deleted_at = excluded.deleted_at,
             vector_clock = excluded.vector_clock,
             source_peer_id = excluded.source_peer_id,
             sync_status = 'synced'",
        params![
            id,
            title,
            content,
            created,
            updated_at,
            version,
            deleted_at,
            vector_clock,
            source_peer_id
        ],
    )?;
    Ok(())
}

pub fn get_note_sync_status(conn: &Connection, id: &str) -> Result<String> {
    let status = conn
        .query_row(
            "SELECT sync_status FROM notes WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()?;
    Ok(status.unwrap_or_else(|| "unknown".to_string()))
}

// ---------------------------------------------------------------------------
// File transfer
// ---------------------------------------------------------------------------

pub fn create_file_transfer(
    conn: &Connection,
    id: &str,
    peer_id: &str,
    file_name: &str,
    file_size: i64,
    file_hash: &str,
    direction: &str,
) -> Result<()> {
    let now = now_millis();
    conn.execute(
        "INSERT INTO file_transfers (id, peer_id, file_name, file_size, file_hash, status, direction, created_at, progress)
         VALUES (?1, ?2, ?3, ?4, ?5, 'pending', ?6, ?7, 0)",
        params![id, peer_id, file_name, file_size, file_hash, direction, now],
    )?;
    Ok(())
}

pub fn set_file_transfer_local_path(conn: &Connection, id: &str, local_path: &str) -> Result<()> {
    conn.execute(
        "UPDATE file_transfers SET local_path = ?2 WHERE id = ?1",
        params![id, local_path],
    )?;
    Ok(())
}

pub fn update_file_transfer_status(conn: &Connection, id: &str, status: &str) -> Result<()> {
    let now = now_millis();
    let completed = matches!(status, "completed" | "failed" | "cancelled");
    let affected = conn.execute(
        "UPDATE file_transfers
         SET status = ?2,
             completed_at = CASE WHEN ?3 THEN ?4 ELSE completed_at END
         WHERE id = ?1",
        params![id, status, completed as i64, now],
    )?;
    if affected == 0 {
        return Err(DropleError::NotFound);
    }
    Ok(())
}

pub fn update_file_transfer_progress(conn: &Connection, id: &str, progress: i64) -> Result<()> {
    let affected = conn.execute(
        "UPDATE file_transfers SET progress = ?2 WHERE id = ?1",
        params![id, progress],
    )?;
    if affected == 0 {
        return Err(DropleError::NotFound);
    }
    Ok(())
}

pub fn list_file_transfers(conn: &Connection) -> Result<Vec<FileTransferView>> {
    let mut stmt = conn.prepare(
        "SELECT id, peer_id, file_name, file_size, file_hash, status, direction,
                created_at, completed_at, local_path, progress
         FROM file_transfers
         ORDER BY created_at DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(FileTransferView {
            id: row.get(0)?,
            peer_id: row.get(1)?,
            file_name: row.get(2)?,
            file_size: row.get(3)?,
            file_hash: row.get(4)?,
            status: row.get(5)?,
            direction: row.get(6)?,
            created_at: row.get(7)?,
            completed_at: row.get(8)?,
            local_path: row.get(9)?,
            progress: row.get(10)?,
        })
    })?;
    let mut transfers = Vec::new();
    for row in rows {
        transfers.push(row?);
    }
    Ok(transfers)
}

pub fn get_file_transfer(conn: &Connection, id: &str) -> Result<FileTransferView> {
    let view = conn
        .query_row(
            "SELECT id, peer_id, file_name, file_size, file_hash, status, direction,
                    created_at, completed_at, local_path, progress
             FROM file_transfers WHERE id = ?1",
            params![id],
            |row| {
                Ok(FileTransferView {
                    id: row.get(0)?,
                    peer_id: row.get(1)?,
                    file_name: row.get(2)?,
                    file_size: row.get(3)?,
                    file_hash: row.get(4)?,
                    status: row.get(5)?,
                    direction: row.get(6)?,
                    created_at: row.get(7)?,
                    completed_at: row.get(8)?,
                    local_path: row.get(9)?,
                    progress: row.get(10)?,
                })
            },
        )
        .optional()?;
    view.ok_or(DropleError::NotFound)
}

pub fn get_file_transfer_status(conn: &Connection, id: &str) -> Result<String> {
    let status = conn
        .query_row(
            "SELECT status FROM file_transfers WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .optional()?;
    status.ok_or(DropleError::NotFound)
}

// ---------------------------------------------------------------------------
// Backup history
// ---------------------------------------------------------------------------

pub fn upsert_backup(
    conn: &Connection,
    id: &str,
    created_at: i64,
    size: i64,
    status: &str,
    local_checksum: Option<&str>,
) -> Result<()> {
    conn.execute(
        "INSERT INTO backups (id, created_at, size, status, local_checksum)
         VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(id) DO UPDATE SET
             created_at = excluded.created_at,
             size = excluded.size,
             status = excluded.status,
             local_checksum = excluded.local_checksum",
        params![id, created_at, size, status, local_checksum],
    )?;
    Ok(())
}

pub fn update_backup_status(conn: &Connection, id: &str, status: &str) -> Result<()> {
    conn.execute(
        "UPDATE backups SET status = ?2 WHERE id = ?1",
        params![id, status],
    )?;
    Ok(())
}

pub fn list_backups(conn: &Connection) -> Result<Vec<BackupView>> {
    let mut stmt = conn.prepare(
        "SELECT id, created_at, size, status, local_checksum
         FROM backups ORDER BY created_at DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(BackupView {
            id: row.get(0)?,
            created_at: row.get(1)?,
            size: row.get(2)?,
            status: row.get(3)?,
            local_checksum: row.get(4)?,
        })
    })?;
    let mut backups = Vec::new();
    for row in rows {
        backups.push(row?);
    }
    Ok(backups)
}

pub fn get_backup(conn: &Connection, id: &str) -> Result<BackupView> {
    let view = conn
        .query_row(
            "SELECT id, created_at, size, status, local_checksum
             FROM backups WHERE id = ?1",
            params![id],
            |row| {
                Ok(BackupView {
                    id: row.get(0)?,
                    created_at: row.get(1)?,
                    size: row.get(2)?,
                    status: row.get(3)?,
                    local_checksum: row.get(4)?,
                })
            },
        )
        .optional()?;
    view.ok_or(DropleError::NotFound)
}

pub fn delete_backup(conn: &Connection, id: &str) -> Result<()> {
    conn.execute("DELETE FROM backups WHERE id = ?1", params![id])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conn() -> Connection {
        let conn = Connection::open_in_memory().expect("open");
        init_schema(&conn).expect("schema");
        conn
    }

    #[test]
    fn note_crud_and_sync_state() {
        let conn = conn();
        let id = create_note(&conn, "Judul", "Isi").expect("create");
        let note = get_note(&conn, &id).expect("get");
        assert_eq!(note.title, "Judul");
        assert_eq!(note.sync_status, "pending");

        update_note(&conn, &id, "Judul2", "Isi2").expect("update");
        let note = get_note(&conn, &id).expect("get2");
        assert_eq!(note.version, 2);

        mark_note_synced(&conn, &id, "{\"p\":1}", Some("p")).expect("synced");
        assert_eq!(get_note_sync_status(&conn, &id).unwrap(), "synced");

        delete_note(&conn, &id).expect("delete");
        assert!(matches!(get_note(&conn, &id), Err(DropleError::NotFound)));
        assert!(get_note_any(&conn, &id).unwrap().deleted_at.is_some());
    }

    #[test]
    fn upsert_note_from_sync_inserts_new_note() {
        let conn = conn();
        upsert_note_from_sync(
            &conn,
            "remote-1",
            "Remote",
            "Body",
            "{\"r\":1}",
            "r",
            1000,
            3,
            None,
            900,
        )
        .expect("upsert");
        let note = get_note(&conn, "remote-1").expect("get");
        assert_eq!(note.title, "Remote");
        assert_eq!(note.sync_status, "synced");
    }

    #[test]
    fn file_transfer_progress_and_status() {
        let conn = conn();
        create_file_transfer(&conn, "t1", "peer", "a.txt", 10, "hash", "send").unwrap();
        update_file_transfer_progress(&conn, "t1", 5).unwrap();
        update_file_transfer_status(&conn, "t1", "completed").unwrap();
        let view = get_file_transfer(&conn, "t1").unwrap();
        assert_eq!(view.progress, 5);
        assert!(view.completed_at.is_some());
    }

    #[test]
    fn migration_adds_legacy_columns() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT NOT NULL, content TEXT NOT NULL,
                created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
                version INTEGER NOT NULL DEFAULT 1, deleted_at INTEGER, is_favorite INTEGER DEFAULT 0);
             CREATE TABLE file_transfers (id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, file_name TEXT NOT NULL,
                file_size INTEGER NOT NULL, file_hash TEXT NOT NULL, status TEXT NOT NULL,
                direction TEXT NOT NULL, created_at INTEGER NOT NULL,
                completed_at INTEGER, local_path TEXT);
             CREATE TABLE peers (id TEXT PRIMARY KEY, name TEXT NOT NULL, public_key TEXT NOT NULL,
                last_seen INTEGER, paired_at INTEGER NOT NULL);",
        )
        .unwrap();
        init_schema(&conn).unwrap();
        assert!(column_exists(&conn, "notes", "sync_status").unwrap());
        assert!(column_exists(&conn, "file_transfers", "progress").unwrap());
        assert!(column_exists(&conn, "peers", "fingerprint").unwrap());
    }
}
