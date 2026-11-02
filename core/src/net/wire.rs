use serde::{Deserialize, Serialize};

use crate::sync::protocol::NoteDelta;

/// Pesan aplikasi yang dipertukarkan antar-peer melalui protokol `/drople/wire/1`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WireMessage {
    PairingRequest,
    Sync {
        deltas: Vec<NoteDelta>,
    },
    FileOffer {
        transfer_id: String,
        file_name: String,
        file_size: i64,
        file_hash: String,
    },
    FileChunk {
        transfer_id: String,
        index: u32,
        total: u32,
        chunk_hash: String,
        data: String,
    },
    FileDone {
        transfer_id: String,
    },
    Ack {
        ok: bool,
        message: String,
    },
}

impl WireMessage {
    pub fn ack(message: impl Into<String>) -> Self {
        WireMessage::Ack {
            ok: true,
            message: message.into(),
        }
    }

    pub fn nack(message: impl Into<String>) -> Self {
        WireMessage::Ack {
            ok: false,
            message: message.into(),
        }
    }
}
