use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use rand::RngCore;
use sha2::{Digest, Sha256};

use crate::error::{DropleError, Result};

pub const NONCE_LEN: usize = 24;
pub const TAG_LEN: usize = 16;
pub const KEY_LEN: usize = 32;
pub const SALT_LEN: usize = 16;

/// Menurunkan kunci E2EE dari identitas peer dan salt acak.
pub fn derive_e2ee_key(peer_id: &str, salt: &[u8; SALT_LEN]) -> [u8; KEY_LEN] {
    let mut hasher = Sha256::new();
    hasher.update(peer_id.as_bytes());
    hasher.update(salt);
    let result = hasher.finalize();
    let mut key = [0u8; KEY_LEN];
    key.copy_from_slice(&result);
    key
}

/// Enkripsi dengan XChaCha20-Poly1305.
/// Output: `[nonce 24 byte][ciphertext + tag]`.
pub fn encrypt(plaintext: &[u8], key: &[u8; KEY_LEN]) -> Result<Vec<u8>> {
    let mut nonce = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut nonce);

    let cipher = XChaCha20Poly1305::new(Key::from_slice(key));
    let ciphertext = cipher
        .encrypt(XNonce::from_slice(&nonce), plaintext)
        .map_err(|e| DropleError::Crypto(format!("enkripsi gagal: {e}")))?;

    let mut output = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    output.extend_from_slice(&nonce);
    output.extend_from_slice(&ciphertext);
    Ok(output)
}

/// Dekripsi payload berformat `[nonce 24 byte][ciphertext + tag]`.
pub fn decrypt(payload: &[u8], key: &[u8; KEY_LEN]) -> Result<Vec<u8>> {
    if payload.len() < NONCE_LEN + TAG_LEN {
        return Err(DropleError::Crypto("ciphertext terlalu pendek".into()));
    }

    let (nonce, ciphertext) = payload.split_at(NONCE_LEN);
    let cipher = XChaCha20Poly1305::new(Key::from_slice(key));
    cipher
        .decrypt(XNonce::from_slice(nonce), ciphertext)
        .map_err(|e| DropleError::Crypto(format!("dekripsi gagal: {e}")))
}

pub fn generate_salt() -> [u8; SALT_LEN] {
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    salt
}

pub fn random_bytes<const N: usize>() -> [u8; N] {
    let mut bytes = [0u8; N];
    rand::thread_rng().fill_bytes(&mut bytes);
    bytes
}

pub fn sha256_hex(data: &[u8]) -> String {
    let digest = Sha256::digest(data);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> [u8; KEY_LEN] {
        let mut key = [0u8; KEY_LEN];
        for (i, byte) in key.iter_mut().enumerate() {
            *byte = i as u8;
        }
        key
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let key = test_key();
        let plaintext = b"Hello, Drople E2EE!";
        let encrypted = encrypt(plaintext, &key).expect("encrypt");
        assert_ne!(encrypted, plaintext);
        let decrypted = decrypt(&encrypted, &key).expect("decrypt");
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn decrypt_rejects_tampering() {
        let key = test_key();
        let mut encrypted = encrypt(b"secret", &key).unwrap();
        let last = encrypted.len() - 1;
        encrypted[last] ^= 0x01;
        assert!(matches!(decrypt(&encrypted, &key), Err(DropleError::Crypto(_))));
    }

    #[test]
    fn decrypt_rejects_short_payload() {
        assert!(matches!(
            decrypt(&[0u8; 8], &test_key()),
            Err(DropleError::Crypto(_))
        ));
    }

    #[test]
    fn derive_key_is_deterministic_and_salt_dependent() {
        let salt = [7u8; SALT_LEN];
        let a = derive_e2ee_key("peer_a", &salt);
        let b = derive_e2ee_key("peer_a", &salt);
        let c = derive_e2ee_key("peer_b", &salt);
        assert_eq!(a, b);
        assert_ne!(a, c);
    }
}
