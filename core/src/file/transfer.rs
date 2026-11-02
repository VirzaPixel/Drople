use serde::Serialize;
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::error::{DropleError, Result};

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Status transfer file.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub enum TransferStatus {
    Pending,
    Active,
    Completed,
    Failed,
    Cancelled,
}

impl std::fmt::Display for TransferStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransferStatus::Pending => write!(f, "pending"),
            TransferStatus::Active => write!(f, "active"),
            TransferStatus::Completed => write!(f, "completed"),
            TransferStatus::Failed => write!(f, "failed"),
            TransferStatus::Cancelled => write!(f, "cancelled"),
        }
    }
}

/// Arah transfer.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub enum TransferDirection {
    Send,
    Receive,
}

impl std::fmt::Display for TransferDirection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransferDirection::Send => write!(f, "send"),
            TransferDirection::Receive => write!(f, "receive"),
        }
    }
}

/// Informasi transfer file.
#[derive(Debug, Clone, Serialize)]
pub struct FileTransfer {
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

impl FileTransfer {
    pub fn new(
        id: String,
        peer_id: String,
        file_name: String,
        file_size: i64,
        file_hash: String,
        direction: TransferDirection,
    ) -> Self {
        FileTransfer {
            id,
            peer_id,
            file_name,
            file_size,
            file_hash,
            status: TransferStatus::Pending.to_string(),
            direction: direction.to_string(),
            created_at: now_millis(),
            completed_at: None,
            local_path: None,
            progress: 0,
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

/// State machine untuk semua transfer file aktif.
pub struct TransferManager {
    transfers: HashMap<String, FileTransfer>,
}

impl TransferManager {
    pub fn new() -> Self {
        TransferManager {
            transfers: HashMap::new(),
        }
    }

    pub fn add(&mut self, transfer: FileTransfer) {
        self.transfers.insert(transfer.id.clone(), transfer);
    }

    pub fn get(&self, id: &str) -> Option<&FileTransfer> {
        self.transfers.get(id)
    }

    pub fn get_mut(&mut self, id: &str) -> Option<&mut FileTransfer> {
        self.transfers.get_mut(id)
    }

    pub fn list(&self) -> Vec<FileTransfer> {
        let mut t: Vec<FileTransfer> = self.transfers.values().cloned().collect();
        t.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        t
    }

    pub fn update_status(&mut self, id: &str, status: TransferStatus) -> Result<()> {
        if let Some(t) = self.transfers.get_mut(id) {
            t.status = status.to_string();
            if status == TransferStatus::Completed || status == TransferStatus::Failed {
                t.completed_at = Some(now_millis());
            }
            Ok(())
        } else {
            Err(DropleError::NotFound)
        }
    }

    pub fn update_progress(&mut self, id: &str, bytes: i64) -> Result<()> {
        if let Some(t) = self.transfers.get_mut(id) {
            t.progress = bytes;
            if t.progress >= t.file_size {
                t.status = TransferStatus::Completed.to_string();
                t.completed_at = Some(now_millis());
            }
            Ok(())
        } else {
            Err(DropleError::NotFound)
        }
    }

    pub fn remove(&mut self, id: &str) -> Option<FileTransfer> {
        self.transfers.remove(id)
    }

    pub fn len(&self) -> usize {
        self.transfers.len()
    }

    pub fn is_empty(&self) -> bool {
        self.transfers.is_empty()
    }
}

impl Default for TransferManager {
    fn default() -> Self {
        Self::new()
    }
}
