use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use libp2p::identity::{Keypair, PublicKey};
use rusqlite::Connection;

use crate::crypto::sha256_hex;
use crate::error::{DropleError, Result};
use crate::{db, with_engine};

const SETTING_KEY: &str = "identity_keypair";

/// Memuat keypair Ed25519 dari tabel `settings`, atau membuat baru bila belum ada.
pub fn load_or_create_from(conn: &Connection) -> Result<Keypair> {
    if let Some(encoded) = db::get_setting(conn, SETTING_KEY)? {
        let bytes = B64
            .decode(encoded.trim())
            .map_err(|e| DropleError::Internal(format!("identity base64 tidak valid: {e}")))?;
        return Keypair::from_protobuf_encoding(&bytes)
            .map_err(|e| DropleError::Internal(format!("identity keypair tidak valid: {e}")));
    }

    let keypair = Keypair::generate_ed25519();
    let bytes = keypair
        .to_protobuf_encoding()
        .map_err(|e| DropleError::Internal(format!("gagal encode identity: {e}")))?;
    db::set_setting(conn, SETTING_KEY, &B64.encode(bytes))?;
    Ok(keypair)
}

/// Versi yang memakai engine global.
pub fn load_or_create() -> Result<Keypair> {
    with_engine(|e| load_or_create_from(&e.conn))
}

/// Fingerprint visual dari public key: 16 karakter hex dikelompokkan 4.
pub fn fingerprint_of(public: &PublicKey) -> String {
    let bytes = public.encode_protobuf();
    let digest = sha256_hex(&bytes);
    let short = &digest[..16];
    short
        .as_bytes()
        .chunks(4)
        .map(|c| String::from_utf8_lossy(c).to_ascii_uppercase())
        .collect::<Vec<_>>()
        .join("-")
}

pub fn fingerprint_for(keypair: &Keypair) -> String {
    fingerprint_of(&keypair.public())
}

/// Fingerprint identitas lokal (dibuat bila belum ada).
pub fn local_fingerprint() -> Result<String> {
    let keypair = load_or_create()?;
    Ok(fingerprint_for(&keypair))
}

pub fn local_peer_id_string() -> Result<String> {
    let keypair = load_or_create()?;
    Ok(keypair.public().to_peer_id().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_persist() {
        let conn = Connection::open_in_memory().expect("open");
        db::init_schema(&conn).expect("schema");

        let first = load_or_create_from(&conn).expect("first");
        let second = load_or_create_from(&conn).expect("second");

        assert_eq!(
            first.public().to_peer_id(),
            second.public().to_peer_id(),
            "keypair harus sama setelah dimuat ulang"
        );
        assert_eq!(fingerprint_for(&first), fingerprint_for(&second));
    }

    #[test]
    fn fingerprint_format_is_stable() {
        let keypair = Keypair::generate_ed25519();
        let a = fingerprint_for(&keypair);
        let b = fingerprint_for(&keypair);
        assert_eq!(a, b);
        assert_eq!(a.len(), 19);
        assert_eq!(a.matches('-').count(), 3);
    }
}
