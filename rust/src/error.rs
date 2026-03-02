use std::fmt;

/// Errors returned by turbotoken operations.
#[derive(Debug)]
pub enum TurbotokenError {
    /// The native C library returned an error code.
    NativeError(isize),
    /// An I/O error occurred (file access, etc.).
    IoError(std::io::Error),
    /// The requested encoding name is not recognized.
    InvalidEncoding(String),
    /// Failed to download a rank file.
    DownloadError(String),
}

impl fmt::Display for TurbotokenError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TurbotokenError::NativeError(code) => {
                write!(f, "turbotoken native error (code {code})")
            }
            TurbotokenError::IoError(e) => write!(f, "I/O error: {e}"),
            TurbotokenError::InvalidEncoding(name) => {
                write!(f, "unknown encoding: {name:?}")
            }
            TurbotokenError::DownloadError(msg) => {
                write!(f, "download error: {msg}")
            }
        }
    }
}

impl std::error::Error for TurbotokenError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            TurbotokenError::IoError(e) => Some(e),
            _ => None,
        }
    }
}

impl From<std::io::Error> for TurbotokenError {
    fn from(e: std::io::Error) -> Self {
        TurbotokenError::IoError(e)
    }
}
