use sha2::{Digest, Sha256};

/// Ukuran chunk default: 64 KB.
pub const CHUNK_SIZE: usize = 64 * 1024;

/// Metadata sebuah chunk file.
#[derive(Debug, Clone)]
pub struct FileChunk {
    pub transfer_id: String,
    pub chunk_index: u32,
    pub total_chunks: u32,
    pub data: Vec<u8>,
    pub hash: String,
}

impl FileChunk {
    /// Buat chunk dari data mentah.
    pub fn new(transfer_id: String, chunk_index: u32, total_chunks: u32, data: Vec<u8>) -> Self {
        let hash = Sha256::digest(&data)
            .to_vec()
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>();
        FileChunk {
            transfer_id,
            chunk_index,
            total_chunks,
            data,
            hash,
        }
    }

    /// Verifikasi integritas chunk dengan SHA-256.
    pub fn verify(&self) -> bool {
        let computed = Sha256::digest(&self.data)
            .to_vec()
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>();
        computed == self.hash
    }

    /// Ukuran data dalam bytes.
    pub fn size(&self) -> usize {
        self.data.len()
    }
}

/// Hitung SHA-256 hash dari file.
pub fn file_hash(path: &std::path::Path) -> Result<String, std::io::Error> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];
    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        hasher.update(&buffer[..n]);
    }
    Ok(hasher
        .finalize()
        .to_vec()
        .iter()
        .map(|b| format!("{:02x}", b))
        .collect::<String>())
}

/// Baca file dan pecah menjadi daftar FileChunk.
pub fn read_file_chunks(
    path: &std::path::Path,
    transfer_id: &str,
) -> Result<Vec<FileChunk>, std::io::Error> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let metadata = file.metadata()?;
    let file_size = metadata.len() as usize;
    let total_chunks = (file_size + CHUNK_SIZE - 1) / CHUNK_SIZE;

    let mut chunks = Vec::with_capacity(total_chunks);
    let mut buffer = vec![0u8; CHUNK_SIZE];
    let mut index: u32 = 0;

    loop {
        let n = file.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        let chunk_data = buffer[..n].to_vec();
        chunks.push(FileChunk::new(
            transfer_id.to_string(),
            index,
            total_chunks as u32,
            chunk_data,
        ));
        index += 1;
    }

    Ok(chunks)
}

/// Tulis chunk ke file output pada offset yang benar.
pub fn write_chunk_to_file(
    path: &std::path::Path,
    chunk: &FileChunk,
) -> Result<(), std::io::Error> {
    use std::io::{Seek, SeekFrom, Write};
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(path)?;
    file.seek(SeekFrom::Start(
        (chunk.chunk_index as u64) * CHUNK_SIZE as u64,
    ))?;
    file.write_all(&chunk.data)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn chunk_hash_verification() {
        let data = b"Hello, Drople file transfer!";
        let chunk = FileChunk::new("transfer1".to_string(), 0, 1, data.to_vec());
        assert!(chunk.verify());
    }

    #[test]
    fn chunk_hash_tamper_detection() {
        let data = b"Hello, Drople file transfer!";
        let mut chunk = FileChunk::new("transfer1".to_string(), 0, 1, data.to_vec());
        chunk.data[0] ^= 0xFF; // ubah satu byte
        assert!(!chunk.verify());
    }

    #[test]
    fn file_chunking_roundtrip() {
        let dir = std::env::temp_dir();
        let path = dir.join(format!("drople_test_{}.bin", uuid::Uuid::new_v4()));
        {
            let mut file = std::fs::File::create(&path).unwrap();
            file.write_all(b"Hello World! This is a test file for Drople P2P transfer.")
                .unwrap();
        }

        let transfer_id = "test_transfer_1".to_string();
        let chunks = read_file_chunks(&path, &transfer_id).unwrap();
        assert!(chunks.len() >= 1);
        assert_eq!(chunks[0].transfer_id, transfer_id);
        assert_eq!(chunks[0].chunk_index, 0);
        assert!(chunks.iter().all(|c| c.verify()));

        // Verifikasi total ukuran
        let total_size: usize = chunks.iter().map(|c| c.size()).sum();
        let metadata = std::fs::metadata(&path).unwrap();
        assert_eq!(total_size, metadata.len() as usize);

        // Cleanup
        let _ = std::fs::remove_file(&path);
    }
}
