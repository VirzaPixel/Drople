pub mod identity;
pub mod node;
pub mod pairing;
pub mod wire;

use std::sync::{Mutex, MutexGuard, OnceLock};

use crate::db;
use crate::error::{DropleError, Result};
use crate::with_engine;
use node::NodeHandle;

static NETWORK: OnceLock<Mutex<Option<NodeHandle>>> = OnceLock::new();

fn slot() -> &'static Mutex<Option<NodeHandle>> {
    NETWORK.get_or_init(|| Mutex::new(None))
}

fn lock() -> Result<MutexGuard<'static, Option<NodeHandle>>> {
    slot()
        .lock()
        .map_err(|_| DropleError::Internal("network lock poisoned".into()))
}

pub fn is_running() -> bool {
    matches!(slot().lock(), Ok(guard) if guard.is_some())
}

pub fn start() -> Result<()> {
    if is_running() {
        return Ok(());
    }

    let keypair = identity::load_or_create()?;
    let db_path = with_engine(|e| Ok(e.path.clone()))?;
    let handle = node::spawn(keypair, Some(db_path))?;
    handle.wait_listen_addr(std::time::Duration::from_secs(3));

    let mut guard = lock()?;
    *guard = Some(handle);
    Ok(())
}

pub fn stop() {
    if let Ok(mut guard) = slot().lock() {
        if let Some(handle) = guard.take() {
            handle.stop();
        }
    }
}

fn handle_with<T>(f: impl FnOnce(&NodeHandle) -> Result<T>) -> Result<T> {
    let guard = lock()?;
    match guard.as_ref() {
        Some(handle) => f(handle),
        None => Err(DropleError::NotConnected),
    }
}

pub fn local_peer_id() -> Result<String> {
    handle_with(|h| Ok(h.local_peer_id().to_string()))
}

pub fn local_fingerprint() -> Result<String> {
    handle_with(|h| Ok(h.snapshot().local_fingerprint))
}

pub fn peers_json() -> Result<String> {
    let guard = lock()?;
    let peers = match guard.as_ref() {
        Some(handle) => handle.snapshot().peers.into_values().collect::<Vec<_>>(),
        None => Vec::new(),
    };
    Ok(serde_json::to_string(&peers)?)
}

pub fn pairing_start() -> Result<String> {
    handle_with(|handle| {
        let state = handle.snapshot();
        let addrs = state
            .listen_addrs
            .iter()
            .filter(|a| !a.contains("/ip4/127.0.0.1/") && !a.contains("/ip6/::1/"))
            .cloned()
            .collect::<Vec<_>>();
        Ok(pairing::new_code(
            state.local_peer_id,
            addrs,
            state.local_fingerprint,
        ))
    })
}

pub fn pairing_connect(code: &str) -> Result<()> {
    let payload = pairing::decode(code)?;
    with_engine(|e| {
        db::upsert_peer(
            &e.conn,
            &payload.peer_id,
            "",
            &payload.peer_id,
            &payload.fingerprint,
        )
    })?;
    handle_with(|handle| {
        handle.dial_peer(&payload.peer_id, &payload.addrs);
        Ok(())
    })
}

pub fn add_relay(addr: &str) -> Result<()> {
    handle_with(|handle| {
        handle.add_relay(addr);
        Ok(())
    })
}

/// Meminta sinkronisasi catatan dengan peer tertentu.
pub fn sync_with_peer(peer_id: &str) -> Result<()> {
    if peer_id.trim().is_empty() {
        return Err(DropleError::InvalidInput("peer id kosong".into()));
    }
    handle_with(|handle| {
        handle.request_sync(peer_id);
        Ok(())
    })
}

/// Menjadwalkan pengiriman file ke peer melalui node P2P.
pub fn send_file(peer_id: &str, transfer_id: &str, file_path: &str) -> Result<()> {
    handle_with(|handle| {
        handle.send_file(peer_id, transfer_id, file_path);
        Ok(())
    })
}

/// Menentukan folder tujuan penerimaan file.
pub fn set_receive_dir(path: &str) -> Result<()> {
    let path = path.trim();
    if path.is_empty() {
        return Err(DropleError::InvalidInput("folder tujuan kosong".into()));
    }
    std::fs::create_dir_all(path)
        .map_err(|e| DropleError::Internal(format!("gagal membuat folder tujuan: {e}")))?;
    with_engine(|e| db::set_setting(&e.conn, node::RECEIVE_DIR_SETTING, path))
}
