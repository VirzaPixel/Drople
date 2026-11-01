use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64URL;
use serde::{Deserialize, Serialize};

use crate::error::{DropleError, Result};

pub const PREFIX: &str = "DRO1:";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairingPayload {
    pub peer_id: String,
    pub addrs: Vec<String>,
    #[serde(default)]
    pub nonce: String,
    #[serde(default)]
    pub fingerprint: String,
}

pub fn encode(payload: &PairingPayload) -> String {
    let json = serde_json::to_vec(payload).unwrap_or_default();
    format!("{PREFIX}{}", B64URL.encode(json))
}

pub fn decode(code: &str) -> Result<PairingPayload> {
    let trimmed = code.trim();
    let body = trimmed
        .strip_prefix(PREFIX)
        .ok_or(DropleError::InvalidPairingCode)?;
    let bytes = B64URL
        .decode(body)
        .map_err(|_| DropleError::InvalidPairingCode)?;
    let payload: PairingPayload =
        serde_json::from_slice(&bytes).map_err(|_| DropleError::InvalidPairingCode)?;
    if payload.peer_id.trim().is_empty() {
        return Err(DropleError::InvalidPairingCode);
    }
    Ok(payload)
}

pub fn new_code(
    peer_id: impl Into<String>,
    addrs: Vec<String>,
    fingerprint: impl Into<String>,
) -> String {
    let nonce = uuid::Uuid::new_v4().to_string();
    encode(&PairingPayload {
        peer_id: peer_id.into(),
        addrs,
        nonce,
        fingerprint: fingerprint.into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairing_code_roundtrip() {
        let code = new_code(
            "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN",
            vec!["/ip4/192.168.1.10/tcp/4001".into()],
            "AAAA-BBBB-CCCC-DDDD",
        );
        assert!(code.starts_with(PREFIX));

        let payload = decode(&code).expect("decode");
        assert_eq!(
            payload.peer_id,
            "12D3KooWDpJ7As7BWAwRMfu1VU2WCqNjvq387JEYKDBj4kx6nXTN"
        );
        assert_eq!(payload.addrs, vec!["/ip4/192.168.1.10/tcp/4001"]);
        assert_eq!(payload.fingerprint, "AAAA-BBBB-CCCC-DDDD");
        assert!(!payload.nonce.is_empty());
    }

    #[test]
    fn pairing_code_invalid() {
        assert!(matches!(
            decode("bukan-kode"),
            Err(DropleError::InvalidPairingCode)
        ));
        assert!(matches!(
            decode("DRO1:!!!bukanbase64"),
            Err(DropleError::InvalidPairingCode)
        ));
    }
}
