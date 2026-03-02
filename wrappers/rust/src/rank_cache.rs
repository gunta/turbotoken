use std::fs;
use std::path::PathBuf;

use crate::error::TurbotokenError;
use crate::registry::get_encoding_spec;

/// Return the cache directory for rank files.
///
/// Uses `TURBOTOKEN_CACHE_DIR` env if set, otherwise `~/.cache/turbotoken/`.
pub fn cache_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("TURBOTOKEN_CACHE_DIR") {
        return PathBuf::from(dir);
    }
    dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("turbotoken")
}

/// Ensure a rank file exists locally, downloading it if missing.
/// Returns the path to the cached rank file.
pub fn ensure_rank_file(name: &str) -> Result<PathBuf, TurbotokenError> {
    let spec = get_encoding_spec(name)?;
    let dir = cache_dir();
    let filename = format!("{}.tiktoken", name);
    let path = dir.join(&filename);

    if path.exists() {
        return Ok(path);
    }

    fs::create_dir_all(&dir)?;

    let response = ureq::get(spec.rank_file_url)
        .call()
        .map_err(|e| TurbotokenError::DownloadError(format!("{e}")))?;

    let mut body = Vec::new();
    response
        .into_body()
        .read_to_end(&mut body)
        .map_err(|e| TurbotokenError::DownloadError(format!("read body: {e}")))?;

    // Write atomically via temp file
    let tmp_path = dir.join(format!(".{filename}.tmp"));
    fs::write(&tmp_path, &body)?;
    fs::rename(&tmp_path, &path)?;

    Ok(path)
}

/// Read a rank file's bytes, downloading if needed.
pub fn read_rank_file(name: &str) -> Result<Vec<u8>, TurbotokenError> {
    let path = ensure_rank_file(name)?;
    Ok(fs::read(path)?)
}
