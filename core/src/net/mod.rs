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

pub const DEVICE_NAME_SETTING: &str = "device_name";

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
    let device_name = with_engine(|e| db::get_setting(&e.conn, DEVICE_NAME_SETTING))?
        .filter(|n| !n.trim().is_empty())
        .unwrap_or_else(|| "Perangkat Drople".to_string());
    let handle = node::spawn(keypair, Some(db_path), device_name)?;
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

pub fn local_short_code() -> Result<String> {
    handle_with(|h| Ok(h.snapshot().local_code))
}

/// Menyimpan nama perangkat yang akan terlihat oleh peer lain.
pub fn set_device_name(name: &str) -> Result<()> {
    let name = name.trim();
    if name.is_empty() {
        return Err(DropleError::InvalidInput("nama perangkat kosong".into()));
    }
    let name: String = name.chars().take(48).collect();
    with_engine(|e| db::set_setting(&e.conn, DEVICE_NAME_SETTING, &name))
}

pub fn peers_json() -> Result<String> {
    let guard = lock()?;
    let peers = match guard.as_ref() {
        Some(handle) => handle.snapshot().peers.into_values().collect::<Vec<_>>(),
        None => Vec::new(),
    };
    Ok(serde_json::to_string(&peers)?)
}

pub fn pending_approvals_json() -> Result<String> {
    let guard = lock()?;
    let requests = match guard.as_ref() {
        Some(handle) => {
            let state = handle.snapshot();
            state
                .pending_approvals
                .into_keys()
                .map(|id| {
                    let name = state
                        .peers
                        .get(&id)
                        .map(|peer| peer.name.clone())
                        .unwrap_or_default();
                    serde_json::json!({"id": id, "name": name})
                })
                .collect::<Vec<_>>()
        }
        None => Vec::new(),
    };
    Ok(serde_json::to_string(&requests)?)
}

pub fn pairing_notifications_json() -> Result<String> {
    handle_with(|handle| {
        let notifications = handle
            .take_pairing_notifications()
            .into_iter()
            .map(|(peer_id, accepted)| {
                serde_json::json!({
                    "peer_id": peer_id,
                    "accepted": accepted,
                })
            })
            .collect::<Vec<_>>();
        Ok(serde_json::to_string(&notifications)?)
    })
}

pub fn approve_peer(peer_id: &str) -> Result<()> {
    handle_with(|handle| {
        handle.approve_peer(peer_id);
        Ok(())
    })
}

pub fn reject_peer(peer_id: &str) -> Result<()> {
    handle_with(|handle| {
        handle.reject_peer(peer_id);
        Ok(())
    })
}

pub fn disconnect_peer(peer_id: &str) -> Result<()> {
    handle_with(|handle| {
        handle.disconnect_peer(peer_id);
        Ok(())
    })
}

/// Mengembalikan kode pairing pendek 6 karakter untuk perangkat ini.
pub fn pairing_start() -> Result<String> {
    local_short_code()
}

pub fn pairing_connect(code: &str) -> Result<()> {
    let trimmed = code.trim();
    let normalized = pairing::normalize_short(trimmed);

    // Kode pendek (QR 6 karakter) atau kode panjang DRO1:<base64>.
    if !normalized.is_empty() && normalized.len() <= 10 {
        return connect_short_code(&normalized);
    }

    let payload = pairing::decode(trimmed)?;
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
        handle.request_pairing(&payload.peer_id, &payload.addrs);
        Ok(())
    })
}

fn connect_short_code(code: &str) -> Result<()> {
    let targets: Vec<(String, Vec<String>, String)> = handle_with(|handle| {
        let state = handle.snapshot();
        Ok(state
            .peers
            .into_values()
            .filter(|peer| peer.code.eq_ignore_ascii_case(code))
            .map(|peer| (peer.id, peer.addresses, peer.fingerprint))
            .collect())
    })?;

    if targets.is_empty() {
        return Err(DropleError::PairingNotFound);
    }

    for (peer_id, addrs, fingerprint) in &targets {
        with_engine(|e| db::upsert_peer(&e.conn, peer_id, "", peer_id, fingerprint))?;
        handle_with(|handle| {
            handle.request_pairing(peer_id, addrs);
            Ok(())
        })?;
    }
    Ok(())
}

pub fn add_relay(addr: &str) -> Result<()> {
    handle_with(|handle| {
        handle.add_relay(addr);
        Ok(())
    })
}

/// Meminta sinkronisasi catatan dengan peer tertentu.
pub fn sync_with_peer(_peer_id: &str) -> Result<()> {
    Err(DropleError::InvalidInput(
        "sinkronisasi catatan antar perangkat dinonaktifkan".into(),
    ))
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
