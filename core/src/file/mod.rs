pub mod chunking;
pub mod transfer;

use crate::db;
use crate::error::{DropleError, Result};
use crate::with_engine;
use crate::file::transfer::{FileTransfer, TransferDirection, TransferManager};

use std::path::Path;
use uuid::Uuid;

static TRANSFER_MANAGER: once_cell::sync::Lazy<std::sync::Mutex<TransferManager>> =
    once_cell::sync::Lazy::new(|| std::sync::Mutex::new(TransferManager::new()));

fn manager() -> Result<std::sync::MutexGuard<'static, TransferManager>> {
    TRANSFER_MANAGER.lock().map_err(|_| {
        DropleError::Internal("transfer manager lock poisoned".into())
    })
}

/// Mulai mengirim file ke peer.
pub fn file_send(peer_id: &str, file_path: &str) -> Result<String> {
    let path = Path::new(file_path);
    if !path.exists() {
        return Err(DropleError::NotFound);
    }

    let metadata = path.metadata().map_err(|e| {
        DropleError::Internal(format!("gagal baca metadata file: {e}"))
    })?;
    let file_size = metadata.len() as i64;
    let file_hash = chunking::file_hash(path).map_err(|e| {
        DropleError::Internal(format!("gagal hitung hash: {e}"))
    })?;
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| DropleError::Internal("nama file tidak valid".into()))?
        .to_string();

    let id = Uuid::new_v4().to_string();

    // Simpan ke DB
    with_engine(|e| {
        db::create_file_transfer(
            &e.conn,
            &id,
            peer_id,
            &file_name,
            file_size,
            &file_hash,
            "send",
        )?;
        Ok(())
    })?;

    // Tambah ke manager
    let transfer = FileTransfer::new(
        id.clone(),
        peer_id.to_string(),
        file_name,
        file_size,
        file_hash,
        TransferDirection::Send,
    );
    manager()?.add(transfer);

    if let Err(e) = crate::net::send_file(peer_id, &id, file_path) {
        with_engine(|engine| db::update_file_transfer_status(&engine.conn, &id, "failed"))?;
        return Err(e);
    }

    Ok(id)
}

/// Menyiapkan folder tujuan penerimaan file dari peer.
///
/// File yang masuk akan otomatis disimpan ke folder ini saat peer mengirim
/// penawaran transfer. Nilai balik adalah token sesi penerimaan.
pub fn file_receive(peer_id: &str, save_path: &str) -> Result<String> {
    let _ = peer_id;
    crate::net::set_receive_dir(save_path)?;
    Ok(Uuid::new_v4().to_string())
}

/// Dapatkan daftar semua transfer file (JSON).
pub fn file_list() -> Result<String> {
    let transfers = with_engine(|e| db::list_file_transfers(&e.conn))?;
    Ok(serde_json::to_string(&transfers)?)
}

/// Dapatkan status transfer file.
pub fn file_transfer_status(id: &str) -> Result<String> {
    let status = with_engine(|e| db::get_file_transfer_status(&e.conn, id))?;
    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::file::transfer::TransferStatus;

    #[test]
    fn transfer_manager_basic() {
        let mut mgr = TransferManager::new();
        assert!(mgr.is_empty());

        let t = FileTransfer::new(
            "t1".to_string(),
            "peer1".to_string(),
            "test.txt".to_string(),
            100,
            "abc123".to_string(),
            TransferDirection::Send,
        );
        mgr.add(t);
        assert_eq!(mgr.len(), 1);

        let got = mgr.get("t1").unwrap();
        assert_eq!(got.file_name, "test.txt");
        assert_eq!(got.status, "pending");

        mgr.update_status("t1", TransferStatus::Active).unwrap();
        let got = mgr.get("t1").unwrap();
        assert_eq!(got.status, "active");

        mgr.update_progress("t1", 100).unwrap();
        let got = mgr.get("t1").unwrap();
        assert_eq!(got.status, "completed");
    }
}