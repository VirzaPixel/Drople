use argon2::Argon2;
use serde::{Deserialize, Serialize};

use crate::crypto::{self, SALT_LEN};
use crate::db::{self, Note};
use crate::error::{DropleError, Result};

pub const MAGIC: &[u8; 5] = b"DRPL1";
pub const SNAPSHOT_VERSION: u32 = 1;

const WORDS: [&str; 256] = [
    "able", "acid", "acre", "aged", "also", "arch", "army", "atom", "aunt", "auto", "away", "baby",
    "back", "bake", "ball", "band", "bank", "barn", "base", "bath", "beam", "bean", "bear", "beat",
    "bell", "belt", "bend", "best", "bike", "bird", "blue", "boat", "body", "bold", "bone", "book",
    "boot", "born", "boss", "both", "bowl", "bulk", "burn", "bush", "busy", "cake", "call", "calm",
    "camp", "card", "care", "cart", "case", "cash", "cast", "cell", "chat", "chef", "chip", "city",
    "clay", "clip", "club", "coal", "coat", "code", "coin", "cold", "come", "cook", "cool", "copy",
    "cord", "core", "corn", "cost", "crew", "crop", "dark", "data", "date", "dawn", "days", "dead",
    "deal", "dean", "dear", "debt", "deep", "deer", "desk", "dial", "diet", "disc", "disk", "dock",
    "does", "done", "door", "dose", "down", "draw", "drop", "drum", "dual", "duck", "dust", "duty",
    "each", "earn", "ease", "east", "easy", "edge", "else", "even", "ever", "face", "fact", "fail",
    "fair", "fall", "farm", "fast", "fate", "fear", "feed", "feel", "fees", "feet", "fell", "felt",
    "file", "fill", "film", "find", "fine", "fire", "firm", "fish", "five", "flat", "flow", "food",
    "foot", "ford", "form", "fort", "four", "free", "from", "fuel", "full", "fund", "gain", "game",
    "gate", "gear", "gift", "girl", "give", "glad", "goal", "goes", "gold", "golf", "gone", "good",
    "gray", "grew", "grow", "gulf", "hair", "half", "hall", "hand", "hang", "hard", "harm", "hate",
    "have", "head", "hear", "heat", "held", "hell", "help", "here", "hero", "high", "hill", "hire",
    "hold", "hole", "holy", "home", "hope", "host", "hour", "huge", "hunt", "hurt", "idea", "inch",
    "into", "iron", "item", "jack", "jane", "jean", "john", "join", "jump", "jury", "just", "keen",
    "keep", "kent", "kept", "kick", "kind", "king", "knee", "knew", "know", "lack", "lady", "laid",
    "lake", "land", "lane", "last", "late", "lead", "left", "less", "life", "lift", "like", "line",
    "link", "list", "live", "load", "loan", "lock", "long", "look", "loss", "lost", "love", "luck",
    "made", "mail", "main", "make",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotNote {
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
}

impl SnapshotNote {
    pub fn from_note(note: &Note) -> Self {
        Self {
            id: note.id.clone(),
            title: note.title.clone(),
            content: note.content.clone(),
            created_at: note.created_at,
            updated_at: note.updated_at,
            version: note.version,
            is_favorite: note.is_favorite,
            deleted_at: note.deleted_at,
            vector_clock: note.vector_clock.clone(),
            source_peer_id: note.source_peer_id.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Snapshot {
    pub version: u32,
    pub created_at: i64,
    pub notes: Vec<SnapshotNote>,
}

impl Snapshot {
    pub fn from_notes(notes: Vec<Note>) -> Self {
        Self {
            version: SNAPSHOT_VERSION,
            created_at: db::now_millis(),
            notes: notes.iter().map(SnapshotNote::from_note).collect(),
        }
    }

    pub fn to_json(&self) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(self)?)
    }

    pub fn from_json(data: &[u8]) -> Result<Self> {
        let snapshot: Snapshot = serde_json::from_slice(data)?;
        if snapshot.version > SNAPSHOT_VERSION {
            return Err(DropleError::InvalidInput(format!(
                "versi snapshot {} tidak didukung",
                snapshot.version
            )));
        }
        Ok(snapshot)
    }
}

/// Membuat recovery key 12 kata (96 bit entropi).
pub fn generate_recovery_key() -> String {
    let bytes = crypto::random_bytes::<12>();
    bytes
        .iter()
        .map(|b| WORDS[*b as usize])
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn validate_recovery_key(mnemonic: &str) -> Result<()> {
    let words = normalize_words(mnemonic);
    if words.len() != 12 {
        return Err(DropleError::InvalidInput(
            "recovery key harus terdiri dari 12 kata".into(),
        ));
    }
    if words.iter().any(|w| !WORDS.contains(&w.as_str())) {
        return Err(DropleError::InvalidInput(
            "recovery key berisi kata yang tidak dikenal".into(),
        ));
    }
    Ok(())
}

fn normalize_words(mnemonic: &str) -> Vec<String> {
    mnemonic
        .split_whitespace()
        .map(|w| w.to_ascii_lowercase())
        .collect()
}

/// Menurunkan kunci enkripsi snapshot dari recovery key + salt.
pub fn derive_key(mnemonic: &str, salt: &[u8; SALT_LEN]) -> Result<[u8; 32]> {
    validate_recovery_key(mnemonic)?;
    let normalized = normalize_words(mnemonic).join(" ");
    let mut key = [0u8; 32];
    Argon2::default()
        .hash_password_into(normalized.as_bytes(), salt, &mut key)
        .map_err(|e| DropleError::Crypto(format!("gagal menurunkan kunci backup: {e}")))?;
    Ok(key)
}

/// Format blob: `[MAGIC 5][version 1][salt 16][XChaCha20 payload]`.
pub fn encrypt_snapshot(snapshot: &Snapshot, mnemonic: &str) -> Result<Vec<u8>> {
    let salt = crypto::generate_salt();
    let key = derive_key(mnemonic, &salt)?;
    let plaintext = snapshot.to_json()?;
    let ciphertext = crypto::encrypt(&plaintext, &key)?;

    let mut blob = Vec::with_capacity(MAGIC.len() + 1 + SALT_LEN + ciphertext.len());
    blob.extend_from_slice(MAGIC);
    blob.push(SNAPSHOT_VERSION as u8);
    blob.extend_from_slice(&salt);
    blob.extend_from_slice(&ciphertext);
    Ok(blob)
}

pub fn decrypt_snapshot(blob: &[u8], mnemonic: &str) -> Result<Snapshot> {
    let header_len = MAGIC.len() + 1 + SALT_LEN;
    if blob.len() <= header_len {
        return Err(DropleError::Crypto("snapshot terlalu pendek".into()));
    }
    if &blob[..MAGIC.len()] != MAGIC {
        return Err(DropleError::Crypto("format snapshot tidak dikenal".into()));
    }
    let version = blob[MAGIC.len()];
    if version > SNAPSHOT_VERSION as u8 {
        return Err(DropleError::Crypto("versi snapshot tidak didukung".into()));
    }

    let salt_start = MAGIC.len() + 1;
    let mut salt = [0u8; SALT_LEN];
    salt.copy_from_slice(&blob[salt_start..salt_start + SALT_LEN]);

    let key = derive_key(mnemonic, &salt)?;
    let plaintext = crypto::decrypt(&blob[header_len..], &key)?;
    Snapshot::from_json(&plaintext)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_note(id: &str) -> Note {
        Note {
            id: id.into(),
            title: "Judul".into(),
            content: "Isi catatan".into(),
            created_at: 1,
            updated_at: 2,
            version: 1,
            is_favorite: 0,
            deleted_at: None,
            vector_clock: "{}".into(),
            source_peer_id: None,
            sync_status: "pending".into(),
        }
    }

    #[test]
    fn wordlist_has_256_unique_words() {
        let unique: std::collections::HashSet<_> = WORDS.iter().collect();
        assert_eq!(WORDS.len(), 256);
        assert_eq!(unique.len(), 256);
    }

    #[test]
    fn recovery_key_roundtrip() {
        let key = generate_recovery_key();
        assert_eq!(key.split_whitespace().count(), 12);
        validate_recovery_key(&key).unwrap();
        assert!(validate_recovery_key("terlalu pendek").is_err());
    }

    #[test]
    fn snapshot_encrypt_decrypt_roundtrip() {
        let mnemonic = generate_recovery_key();
        let snapshot = Snapshot::from_notes(vec![sample_note("n1")]);
        let blob = encrypt_snapshot(&snapshot, &mnemonic).unwrap();
        assert_eq!(&blob[..MAGIC.len()], MAGIC);

        let restored = decrypt_snapshot(&blob, &mnemonic).unwrap();
        assert_eq!(restored.notes.len(), 1);
        assert_eq!(restored.notes[0].id, "n1");
    }

    #[test]
    fn snapshot_wrong_recovery_key_fails() {
        let snapshot = Snapshot::from_notes(vec![sample_note("n1")]);
        let blob = encrypt_snapshot(&snapshot, &generate_recovery_key()).unwrap();
        assert!(matches!(
            decrypt_snapshot(&blob, &generate_recovery_key()),
            Err(DropleError::Crypto(_))
        ));
    }
}
