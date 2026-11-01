pub mod backup;
pub mod crypto;
pub mod db;
pub mod error;
pub mod ffi;
pub mod file;
pub mod net;
pub mod peers;
pub mod sync;

use std::sync::{Mutex, MutexGuard, OnceLock};

use rusqlite::Connection;

use crate::error::{DropleError, Result};

pub struct Engine {
    pub conn: Connection,
    pub path: String,
}

static ENGINE: OnceLock<Mutex<Option<Engine>>> = OnceLock::new();

fn slot() -> &'static Mutex<Option<Engine>> {
    ENGINE.get_or_init(|| Mutex::new(None))
}

fn lock() -> Result<MutexGuard<'static, Option<Engine>>> {
    slot()
        .lock()
        .map_err(|_| DropleError::Internal("engine lock poisoned".into()))
}

pub fn init(db_path: &str) -> Result<()> {
    let conn = Connection::open(db_path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    db::init_schema(&conn)?;
    let mut guard = lock()?;
    *guard = Some(Engine {
        conn,
        path: db_path.to_string(),
    });
    Ok(())
}

pub fn cleanup() {
    net::stop();
    if let Ok(mut guard) = slot().lock() {
        *guard = None;
    }
}

pub fn with_engine<T>(f: impl FnOnce(&Engine) -> Result<T>) -> Result<T> {
    let guard = lock()?;
    match guard.as_ref() {
        Some(engine) => f(engine),
        None => Err(DropleError::NotInitialized),
    }
}

pub fn db_path() -> Result<String> {
    with_engine(|e| Ok(e.path.clone()))
}

pub fn with_conn<T>(f: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
    with_engine(|e| f(&e.conn))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_crud_roundtrip() {
        init(":memory:").expect("init");

        let id = with_conn(|conn| db::create_note(conn, "Judul", "Isi")).expect("create");
        let note = with_conn(|conn| db::get_note(conn, &id)).expect("get");
        assert_eq!(note.title, "Judul");
        assert_eq!(note.content, "Isi");
        assert_eq!(note.version, 1);

        with_conn(|conn| db::update_note(conn, &id, "Judul2", "Isi2")).expect("update");
        let note = with_conn(|conn| db::get_note(conn, &id)).expect("get2");
        assert_eq!(note.title, "Judul2");
        assert_eq!(note.version, 2);

        let list = with_conn(db::list_notes).expect("list");
        assert_eq!(list.len(), 1);

        with_conn(|conn| db::delete_note(conn, &id)).expect("delete");
        assert!(matches!(
            with_conn(|conn| db::get_note(conn, &id)),
            Err(DropleError::NotFound)
        ));

        cleanup();
    }
}
