use std::time::Duration;

use reqwest::{Client, StatusCode, Url};
use serde::Deserialize;

use crate::db;
use crate::error::{DropleError, Result};
use crate::with_conn;

const TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const FILES_URL: &str = "https://www.googleapis.com/drive/v3/files";
const UPLOAD_URL: &str = "https://www.googleapis.com/upload/drive/v3/files";

pub const KEY_ACCESS: &str = "gdrive_access_token";
pub const KEY_REFRESH: &str = "gdrive_refresh_token";
pub const KEY_EXPIRES: &str = "gdrive_expires_at";
pub const KEY_CONNECTED: &str = "gdrive_connected";
pub const KEY_CLIENT_ID: &str = "gdrive_client_id";
pub const KEY_CLIENT_SECRET: &str = "gdrive_client_secret";
pub const KEY_ROOT_FOLDER: &str = "gdrive_root_folder";

#[derive(Debug, Clone, Default)]
pub struct TokenSet {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RemoteBackup {
    pub id: String,
    pub name: String,
    pub size: i64,
    pub created_at: i64,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    expires_in: Option<i64>,
}

#[derive(Deserialize)]
struct DriveFile {
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    size: Option<String>,
}

#[derive(Deserialize)]
struct DriveList {
    #[serde(default)]
    files: Vec<DriveFile>,
}

fn runtime() -> Result<tokio::runtime::Runtime> {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| DropleError::Internal(format!("gagal membuat runtime backup: {e}")))
}

pub fn load_tokens() -> Result<Option<TokenSet>> {
    with_conn(|conn| {
        let access = db::get_setting(conn, KEY_ACCESS)?;
        let refresh = db::get_setting(conn, KEY_REFRESH)?.unwrap_or_default();
        let expires = db::get_setting(conn, KEY_EXPIRES)?
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0);
        Ok(access.filter(|a| !a.is_empty()).map(|access| TokenSet {
            access_token: access,
            refresh_token: refresh,
            expires_at: expires,
        }))
    })
}

pub fn save_tokens(tokens: &TokenSet) -> Result<()> {
    with_conn(|conn| {
        db::set_setting(conn, KEY_ACCESS, &tokens.access_token)?;
        db::set_setting(conn, KEY_REFRESH, &tokens.refresh_token)?;
        db::set_setting(conn, KEY_EXPIRES, &tokens.expires_at.to_string())?;
        db::set_setting(conn, KEY_CONNECTED, "1")?;
        Ok(())
    })
}

pub fn set_token(access_token: &str, refresh_token: &str, expires_at: i64) -> Result<()> {
    if access_token.trim().is_empty() {
        return Err(DropleError::InvalidInput(
            "access token tidak boleh kosong".into(),
        ));
    }
    save_tokens(&TokenSet {
        access_token: access_token.to_string(),
        refresh_token: refresh_token.to_string(),
        expires_at,
    })
}

pub fn is_connected() -> Result<bool> {
    with_conn(|conn| {
        let connected = db::get_setting(conn, KEY_CONNECTED)?
            .map(|v| v == "1")
            .unwrap_or(false);
        let has_access = db::get_setting(conn, KEY_ACCESS)?
            .map(|v| !v.is_empty())
            .unwrap_or(false);
        Ok(connected && has_access)
    })
}

pub fn disconnect() -> Result<()> {
    with_conn(|conn| {
        db::delete_setting(conn, KEY_ACCESS)?;
        db::delete_setting(conn, KEY_REFRESH)?;
        db::delete_setting(conn, KEY_EXPIRES)?;
        db::set_setting(conn, KEY_CONNECTED, "0")?;
        Ok(())
    })
}

pub fn configured_client_id() -> Result<String> {
    let stored = with_conn(|conn| db::get_setting(conn, KEY_CLIENT_ID))?;
    Ok(stored
        .or_else(|| std::env::var("DROPLE_GOOGLE_CLIENT_ID").ok())
        .unwrap_or_default()
        .trim()
        .to_string())
}

pub fn has_client_secret() -> Result<bool> {
    let stored = with_conn(|conn| db::get_setting(conn, KEY_CLIENT_SECRET))?;
    Ok(stored
        .or_else(|| std::env::var("DROPLE_GOOGLE_CLIENT_SECRET").ok())
        .map(|value| !value.trim().is_empty())
        .unwrap_or(false))
}

/// Menukar authorization code OAuth (loopback + PKCE) menjadi token.
pub fn exchange_code(code: &str, verifier: &str, redirect_uri: &str) -> Result<()> {
    if code.trim().is_empty() || verifier.trim().is_empty() || redirect_uri.trim().is_empty() {
        return Err(DropleError::InvalidInput(
            "code, verifier, dan redirect URI wajib diisi".into(),
        ));
    }
    runtime()?.block_on(exchange_code_async(code, verifier, redirect_uri))
}

async fn exchange_code_async(code: &str, verifier: &str, redirect_uri: &str) -> Result<()> {
    let (client_id, client_secret) = client_credentials()?;
    if client_secret.is_empty() {
        return Err(DropleError::Auth(
            "client secret Google OAuth belum diset".into(),
        ));
    }
    let params = [
        ("client_id", client_id.as_str()),
        ("client_secret", client_secret.as_str()),
        ("code", code),
        ("code_verifier", verifier),
        ("grant_type", "authorization_code"),
        ("redirect_uri", redirect_uri),
    ];
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| DropleError::Internal(format!("gagal membuat HTTP client: {e}")))?;
    let resp = client
        .post(TOKEN_URL)
        .form(&params)
        .send()
        .await
        .map_err(|e| DropleError::Auth(format!("gagal menukar kode OAuth: {e}")))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        return Err(DropleError::Auth(format!(
            "Google menolak kode OAuth ({}): {}",
            status, text
        )));
    }
    let body: TokenResponse = serde_json::from_str(&text)
        .map_err(|e| DropleError::Auth(format!("respons token tidak valid: {e}")))?;
    save_tokens(&TokenSet {
        access_token: body.access_token,
        refresh_token: body.refresh_token.unwrap_or_default(),
        expires_at: db::now_millis() + body.expires_in.unwrap_or(3600) * 1000,
    })
}

fn client_credentials() -> Result<(String, String)> {
    let client_id = configured_client_id()?;
    if client_id.is_empty() {
        return Err(DropleError::Auth(
            "client id Google OAuth belum diset".into(),
        ));
    }
    let stored_secret = with_conn(|conn| db::get_setting(conn, KEY_CLIENT_SECRET))?;
    let client_secret = stored_secret
        .or_else(|| std::env::var("DROPLE_GOOGLE_CLIENT_SECRET").ok())
        .unwrap_or_default()
        .trim()
        .to_string();
    Ok((client_id, client_secret))
}

async fn refresh_token(client: &Client, tokens: &TokenSet) -> Result<TokenSet> {
    if tokens.refresh_token.trim().is_empty() {
        return Err(DropleError::Auth(
            "refresh token kosong; pengguna harus login kembali".into(),
        ));
    }
    let (client_id, client_secret) = client_credentials()?;
    let mut params = vec![
        ("client_id", client_id.as_str()),
        ("refresh_token", tokens.refresh_token.as_str()),
        ("grant_type", "refresh_token"),
    ];
    if !client_secret.is_empty() {
        params.push(("client_secret", client_secret.as_str()));
    }
    let resp = client
        .post(TOKEN_URL)
        .form(&params)
        .send()
        .await
        .map_err(|e| DropleError::Auth(format!("gagal refresh token: {e}")))?;
    if !resp.status().is_success() {
        return Err(DropleError::Auth(format!(
            "refresh token ditolak Google ({})",
            resp.status()
        )));
    }
    let body: TokenResponse = resp
        .json()
        .await
        .map_err(|e| DropleError::Auth(format!("respons token tidak valid: {e}")))?;
    let now = db::now_millis();
    Ok(TokenSet {
        access_token: body.access_token,
        refresh_token: body
            .refresh_token
            .unwrap_or_else(|| tokens.refresh_token.clone()),
        expires_at: now + body.expires_in.unwrap_or(3600) * 1000,
    })
}

async fn access_token(client: &Client) -> Result<String> {
    let tokens = load_tokens()?.ok_or(DropleError::DriveNotConnected)?;
    let now = db::now_millis();
    if tokens.expires_at == 0 || tokens.expires_at > now + 60_000 {
        return Ok(tokens.access_token);
    }
    let refreshed = refresh_token(client, &tokens).await?;
    let token = refreshed.access_token.clone();
    save_tokens(&refreshed)?;
    Ok(token)
}

fn map_status(status: StatusCode, body: &str) -> DropleError {
    match status {
        StatusCode::UNAUTHORIZED => DropleError::Auth(body.to_string()),
        StatusCode::FORBIDDEN if body.contains("quota") => DropleError::QuotaExceeded,
        _ => DropleError::DriveTransfer(format!("HTTP {status}: {body}")),
    }
}

fn multipart_related(metadata: &str, data: &[u8]) -> (String, Vec<u8>) {
    let boundary = format!("drople-{}", uuid::Uuid::new_v4());
    let mut body = Vec::with_capacity(metadata.len() + data.len() + 256);
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Type: application/json; charset=UTF-8\r\n\r\n");
    body.extend_from_slice(metadata.as_bytes());
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Type: application/octet-stream\r\n\r\n");
    body.extend_from_slice(data);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    (format!("multipart/related; boundary={boundary}"), body)
}

async fn upload_async(file_name: &str, data: Vec<u8>) -> Result<String> {
    let client = Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .map_err(|e| DropleError::Internal(format!("gagal membuat HTTP client: {e}")))?;
    let token = access_token(&client).await?;

    let folder = with_conn(|conn| db::get_setting(conn, KEY_ROOT_FOLDER))?
        .unwrap_or_else(|| "appDataFolder".to_string());
    let metadata = serde_json::json!({
        "name": file_name,
        "parents": [folder],
        "mimeType": "application/octet-stream",
    })
    .to_string();
    let (content_type, body) = multipart_related(&metadata, &data);

    let mut url = Url::parse(UPLOAD_URL).expect("url valid");
    url.query_pairs_mut().append_pair("uploadType", "multipart");

    let resp = client
        .post(url)
        .bearer_auth(token)
        .header(reqwest::header::CONTENT_TYPE, content_type)
        .body(body)
        .send()
        .await
        .map_err(|e| DropleError::DriveTransfer(format!("upload gagal: {e}")))?;

    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        return Err(map_status(status, &text));
    }
    let file: DriveFile = serde_json::from_str(&text)
        .map_err(|e| DropleError::DriveTransfer(format!("respons upload tidak valid: {e}")))?;
    Ok(file.id)
}

pub fn upload(file_name: &str, data: Vec<u8>) -> Result<String> {
    runtime()?.block_on(upload_async(file_name, data))
}

async fn list_async() -> Result<Vec<RemoteBackup>> {
    let client = Client::builder()
        .timeout(Duration::from_secs(60))
        .build()
        .map_err(|e| DropleError::Internal(format!("gagal membuat HTTP client: {e}")))?;
    let token = access_token(&client).await?;

    let mut url = Url::parse(FILES_URL).expect("url valid");
    url.query_pairs_mut()
        .append_pair("spaces", "appDataFolder")
        .append_pair("orderBy", "createdTime desc")
        .append_pair(
            "fields",
            "files(id,name,size,createdTime,md5Checksum),nextPageToken",
        )
        .append_pair("pageSize", "100");

    let resp = client
        .get(url)
        .bearer_auth(token)
        .send()
        .await
        .map_err(|e| DropleError::DriveTransfer(format!("list backup gagal: {e}")))?;
    let status = resp.status();
    let text = resp.text().await.unwrap_or_default();
    if !status.is_success() {
        return Err(map_status(status, &text));
    }
    let list: DriveList = serde_json::from_str(&text)
        .map_err(|e| DropleError::DriveTransfer(format!("respons list tidak valid: {e}")))?;

    Ok(list
        .files
        .into_iter()
        .filter(|f| f.name.starts_with("drople-backup-"))
        .map(|f| RemoteBackup {
            id: f.id,
            name: f.name.clone(),
            size: f.size.and_then(|s| s.parse::<i64>().ok()).unwrap_or(0),
            created_at: parse_backup_timestamp(&f.name).unwrap_or(0),
        })
        .collect())
}

pub fn list() -> Result<Vec<RemoteBackup>> {
    runtime()?.block_on(list_async())
}

async fn download_async(file_id: &str) -> Result<Vec<u8>> {
    let client = Client::builder()
        .timeout(Duration::from_secs(120))
        .build()
        .map_err(|e| DropleError::Internal(format!("gagal membuat HTTP client: {e}")))?;
    let token = access_token(&client).await?;

    let mut url = Url::parse(&format!("{FILES_URL}/{file_id}")).expect("url valid");
    url.query_pairs_mut().append_pair("alt", "media");

    let resp = client
        .get(url)
        .bearer_auth(token)
        .send()
        .await
        .map_err(|e| DropleError::DriveTransfer(format!("download gagal: {e}")))?;
    let status = resp.status();
    if !status.is_success() {
        let text = resp.text().await.unwrap_or_default();
        return Err(map_status(status, &text));
    }
    resp.bytes()
        .await
        .map(|b| b.to_vec())
        .map_err(|e| DropleError::DriveTransfer(format!("gagal membaca isi backup: {e}")))
}

pub fn download(file_id: &str) -> Result<Vec<u8>> {
    runtime()?.block_on(download_async(file_id))
}

async fn delete_async(file_id: &str) -> Result<()> {
    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| DropleError::Internal(format!("gagal membuat HTTP client: {e}")))?;
    let token = access_token(&client).await?;

    let url = Url::parse(&format!("{FILES_URL}/{file_id}")).expect("url valid");
    let resp = client
        .delete(url)
        .bearer_auth(token)
        .send()
        .await
        .map_err(|e| DropleError::DriveTransfer(format!("hapus backup gagal: {e}")))?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(map_status(status, &text));
    }
    Ok(())
}

pub fn delete(file_id: &str) -> Result<()> {
    runtime()?.block_on(delete_async(file_id))
}

/// Nama backup: `drople-backup-<unix millis>.drople`.
pub fn backup_file_name(timestamp_ms: i64) -> String {
    format!("drople-backup-{timestamp_ms}.drople")
}

fn parse_backup_timestamp(name: &str) -> Option<i64> {
    name.strip_prefix("drople-backup-")?
        .strip_suffix(".drople")?
        .parse()
        .ok()
}

#[allow(dead_code)]
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backup_name_roundtrip() {
        let name = backup_file_name(1_700_000_000_000);
        assert_eq!(name, "drople-backup-1700000000000.drople");
        assert_eq!(parse_backup_timestamp(&name), Some(1_700_000_000_000));
    }

    #[test]
    fn multipart_related_contains_parts() {
        let (content_type, body) = multipart_related("{\"name\":\"x\"}", b"hello");
        assert!(content_type.starts_with("multipart/related; boundary=drople-"));
        let text = String::from_utf8_lossy(&body);
        assert!(text.contains("application/json"));
        assert!(text.contains("application/octet-stream"));
        assert!(text.contains("hello"));
    }

    #[test]
    fn parse_timestamp_rejects_other_names() {
        assert_eq!(parse_backup_timestamp("catatan.txt"), None);
    }
}
