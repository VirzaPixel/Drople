use thiserror::Error;

#[derive(Debug, Error)]
pub enum DropleError {
    #[error("database error: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("not found")]
    NotFound,

    #[error("core not initialized")]
    NotInitialized,

    #[error("invalid input: {0}")]
    InvalidInput(String),

    #[error("internal error: {0}")]
    Internal(String),

    #[error("not connected to peer")]
    NotConnected,

    #[error("invalid pairing code")]
    InvalidPairingCode,

    #[error("peer dengan kode tersebut belum ditemukan")]
    PairingNotFound,

    #[error("network error: {0}")]
    Network(String),

    #[error("crypto error: {0}")]
    Crypto(String),

    #[error("recovery key is not configured")]
    RecoveryKeyMissing,

    #[error("google drive is not connected")]
    DriveNotConnected,

    #[error("authentication failed: {0}")]
    Auth(String),

    #[error("google drive quota exceeded")]
    QuotaExceeded,

    #[error("google drive transfer failed: {0}")]
    DriveTransfer(String),
}

pub type Result<T> = std::result::Result<T, DropleError>;

impl DropleError {
    /// Kode error standar untuk kesalahan operasional.
    /// Setiap varian error memiliki kode yang unik untuk identifikasi yang jelas.
    pub fn code(&self) -> i32 {
        match self {
            DropleError::Database(_) => 1,
            DropleError::Serialization(_) => 2,
            DropleError::NotFound => 3,
            DropleError::NotInitialized => 4,
            DropleError::InvalidInput(_) => 5,
            DropleError::Internal(_) => 6,
            DropleError::NotConnected => 7,
            DropleError::InvalidPairingCode => 8,
            DropleError::PairingNotFound => 16,
            DropleError::Network(_) => 9,
            DropleError::Crypto(_) => 10,
            DropleError::RecoveryKeyMissing => 11,
            DropleError::DriveNotConnected => 12,
            DropleError::Auth(_) => 13,
            DropleError::QuotaExceeded => 14,
            DropleError::DriveTransfer(_) => 15,
        }
    }

    /// Mendapatkan kategori error untuk logging/monitoring.
    pub fn category(&self) -> &'static str {
        match self {
            DropleError::Database(_) | DropleError::Serialization(_) => "storage",
            DropleError::NotFound | DropleError::NotInitialized => "initialization",
            DropleError::InvalidInput(_) => "input",
            DropleError::Internal(_) => "internal",
            DropleError::NotConnected | DropleError::Network(_) => "network",
            DropleError::InvalidPairingCode | DropleError::PairingNotFound => "pairing",
            DropleError::Crypto(_) => "crypto",
            DropleError::RecoveryKeyMissing => "security",
            DropleError::DriveNotConnected | DropleError::QuotaExceeded | DropleError::DriveTransfer(_) => "google_drive",
            DropleError::Auth(_) => "authentication",
        }
    }
}
