use serde::{Deserialize, Serialize};

use crate::db::Note;

/// Pesan sinkronisasi yang dikirim antar-peer via P2P.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SyncMessage {
    /// Permintaan sinkronisasi: berisi delta lokal milik pengirim.
    SyncRequest { deltas: Vec<NoteDelta> },
    /// Respons sinkronisasi: berisi delta catatan milik penerima.
    SyncResponse { deltas: Vec<NoteDelta> },
}

/// Delta catatan untuk sinkronisasi.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteDelta {
    pub id: String,
    pub title: String,
    pub content: String,
    pub vector_clock: String,
    pub deleted: bool,
    pub deleted_at: Option<i64>,
    pub source_peer_id: String,
    pub updated_at: i64,
    pub version: i64,
    #[serde(default)]
    pub created_at: i64,
}

impl NoteDelta {
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }

    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    pub fn from_note(note: &Note) -> Self {
        Self {
            id: note.id.clone(),
            title: note.title.clone(),
            content: note.content.clone(),
            vector_clock: note.vector_clock.clone(),
            deleted: note.deleted_at.is_some(),
            deleted_at: note.deleted_at,
            source_peer_id: note
                .source_peer_id
                .clone()
                .unwrap_or_else(|| "local".to_string()),
            updated_at: note.updated_at,
            version: note.version,
            created_at: note.created_at,
        }
    }
}
