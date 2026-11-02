use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::db::Note;
use crate::sync::protocol::NoteDelta;

/// Register dengan Last-Writer-Wins (LWW) untuk tiap field catatan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LWWRegister<T> {
    pub value: T,
    pub timestamp: i64,
    pub source: String, // peer_id
}

impl<T: Clone + PartialEq> LWWRegister<T> {
    pub fn merge(&self, other: &Self) -> Self {
        if other.timestamp > self.timestamp {
            other.clone()
        } else if other.timestamp < self.timestamp {
            self.clone()
        } else if other.source > self.source {
            other.clone()
        } else {
            self.clone()
        }
    }
}

/// Representasi CRDT dari sebuah catatan.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteCRDT {
    pub id: String,
    pub title: LWWRegister<String>,
    pub content: LWWRegister<String>,
    pub vector_clock: HashMap<String, i64>,
    pub deleted: bool,
    pub deleted_at: Option<i64>,
    pub version: i64,
    pub source_peer_id: String,
}

impl NoteCRDT {
    pub fn from_db_note(note: &Note) -> Self {
        let mut vc: HashMap<String, i64> = HashMap::new();
        if let Ok(map) = serde_json::from_str::<HashMap<String, i64>>(&note.vector_clock) {
            vc = map;
        }
        NoteCRDT {
            id: note.id.clone(),
            title: LWWRegister {
                value: note.title.clone(),
                timestamp: note.updated_at,
                source: note.source_peer_id.clone().unwrap_or_default(),
            },
            content: LWWRegister {
                value: note.content.clone(),
                timestamp: note.updated_at,
                source: note.source_peer_id.clone().unwrap_or_default(),
            },
            vector_clock: vc,
            deleted: note.deleted_at.is_some(),
            deleted_at: note.deleted_at,
            version: note.version,
            source_peer_id: note.source_peer_id.clone().unwrap_or_default(),
        }
    }

    pub fn from_delta(delta: &NoteDelta) -> Self {
        let mut vc: HashMap<String, i64> = HashMap::new();
        if let Ok(map) = serde_json::from_str::<HashMap<String, i64>>(&delta.vector_clock) {
            vc = map;
        }
        NoteCRDT {
            id: delta.id.clone(),
            title: LWWRegister {
                value: delta.title.clone(),
                timestamp: delta.updated_at,
                source: delta.source_peer_id.clone(),
            },
            content: LWWRegister {
                value: delta.content.clone(),
                timestamp: delta.updated_at,
                source: delta.source_peer_id.clone(),
            },
            vector_clock: vc,
            deleted: delta.deleted,
            deleted_at: delta.deleted_at,
            version: delta.version,
            source_peer_id: delta.source_peer_id.clone(),
        }
    }

    pub fn merge(&self, other: &Self) -> Self {
        let mut merged_vc = self.vector_clock.clone();
        for (peer, clock) in &other.vector_clock {
            merged_vc
                .entry(peer.clone())
                .and_modify(|c| *c = (*c).max(*clock))
                .or_insert(*clock);
        }

        let my_id = self.source_peer_id.clone();
        *merged_vc.entry(my_id).or_insert(0) += 1;

        let title = self.title.merge(&other.title);
        let content = self.content.merge(&other.content);

        let deleted = self.deleted || other.deleted;
        let deleted_at = match (self.deleted_at, other.deleted_at) {
            (Some(a), Some(b)) => Some(a.max(b)),
            (Some(a), None) => Some(a),
            (None, Some(b)) => Some(b),
            (None, None) => None,
        };

        let version = self.version.max(other.version) + 1;

        let source_peer_id = if title.timestamp >= content.timestamp {
            title.source.clone()
        } else {
            content.source.clone()
        };

        NoteCRDT {
            id: self.id.clone(),
            title,
            content,
            vector_clock: merged_vc,
            deleted,
            deleted_at,
            version,
            source_peer_id,
        }
    }

    pub fn vector_clock_json(&self) -> String {
        serde_json::to_string(&self.vector_clock).unwrap_or_default()
    }

    pub fn latest_timestamp(&self) -> i64 {
        self.title.timestamp.max(self.content.timestamp)
    }
}

/// Merge dua catatan dengan CRDT.
pub fn merge_notes(local: &NoteCRDT, remote: &NoteCRDT, _local_peer_id: &str) -> NoteCRDT {
    local.merge(remote)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_crdt(id: &str, title_ts: i64, content_ts: i64, source: &str) -> NoteCRDT {
        NoteCRDT {
            id: id.to_string(),
            title: LWWRegister {
                value: format!("title_{}", title_ts),
                timestamp: title_ts,
                source: source.to_string(),
            },
            content: LWWRegister {
                value: format!("content_{}", content_ts),
                timestamp: content_ts,
                source: source.to_string(),
            },
            vector_clock: HashMap::from([(source.to_string(), 1)]),
            deleted: false,
            deleted_at: None,
            version: 1,
            source_peer_id: source.to_string(),
        }
    }

    #[test]
    fn lww_register_higher_timestamp_wins() {
        let a = LWWRegister {
            value: "old".to_string(),
            timestamp: 100,
            source: "peerA".to_string(),
        };
        let b = LWWRegister {
            value: "new".to_string(),
            timestamp: 200,
            source: "peerB".to_string(),
        };
        let merged = a.merge(&b);
        assert_eq!(merged.value, "new");
        assert_eq!(merged.timestamp, 200);
        assert_eq!(merged.source, "peerB");
    }

    #[test]
    fn lww_register_same_timestamp_tie_break_by_source() {
        let a = LWWRegister {
            value: "fromA".to_string(),
            timestamp: 100,
            source: "peerA".to_string(),
        };
        let b = LWWRegister {
            value: "fromB".to_string(),
            timestamp: 100,
            source: "peerB".to_string(),
        };
        let merged = a.merge(&b);
        assert_eq!(merged.value, "fromB");
        assert_eq!(merged.source, "peerB");
    }

    #[test]
    fn crdt_merge_local_newer_wins() {
        let local = make_crdt("note1", 200, 200, "peerA");
        let remote = make_crdt("note1", 100, 100, "peerB");
        let merged = local.merge(&remote);
        assert_eq!(merged.title.value, "title_200");
        assert_eq!(merged.content.value, "content_200");
        assert_eq!(merged.source_peer_id, "peerA");
    }

    #[test]
    fn crdt_merge_remote_newer_wins() {
        let local = make_crdt("note1", 100, 100, "peerA");
        let remote = make_crdt("note1", 200, 200, "peerB");
        let merged = local.merge(&remote);
        assert_eq!(merged.title.value, "title_200");
        assert_eq!(merged.content.value, "content_200");
        assert_eq!(merged.source_peer_id, "peerB");
    }

    #[test]
    fn crdt_merge_concurrent_different_fields() {
        let mut local = make_crdt("note1", 200, 100, "peerA");
        local.title.value = "local_title".to_string();
        let mut remote = make_crdt("note1", 100, 200, "peerB");
        remote.content.value = "remote_content".to_string();

        let merged = local.merge(&remote);
        assert_eq!(merged.title.value, "local_title");
        assert_eq!(merged.content.value, "remote_content");
    }

    #[test]
    fn vector_clock_merge() {
        let mut vc1 = HashMap::new();
        vc1.insert("peerA".to_string(), 5);
        vc1.insert("peerB".to_string(), 3);

        let mut vc2 = HashMap::new();
        vc2.insert("peerA".to_string(), 2);
        vc2.insert("peerC".to_string(), 7);

        let mut local = make_crdt("note1", 100, 100, "peerA");
        local.vector_clock = vc1;
        let mut remote = make_crdt("note1", 100, 100, "peerB");
        remote.vector_clock = vc2;

        let merged = local.merge(&remote);
        assert_eq!(merged.vector_clock.get("peerA"), Some(&6));
        assert_eq!(merged.vector_clock.get("peerB"), Some(&3));
        assert_eq!(merged.vector_clock.get("peerC"), Some(&7));
        assert!(merged.vector_clock.get("peerA").unwrap() > &5);
    }
}
