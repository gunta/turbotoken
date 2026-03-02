package turbotoken

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
)

var (
	cacheMu sync.Mutex
)

// CacheDir returns the directory used for caching rank files.
// Uses TURBOTOKEN_CACHE_DIR if set, otherwise ~/.cache/turbotoken/.
func CacheDir() string {
	if dir := os.Getenv("TURBOTOKEN_CACHE_DIR"); dir != "" {
		return dir
	}
	home, err := os.UserCacheDir()
	if err != nil {
		home = os.TempDir()
	}
	return filepath.Join(home, "turbotoken")
}

// EnsureRankFile ensures the rank file for the given encoding exists locally,
// downloading it if necessary. Returns the path to the local file.
func EnsureRankFile(name string) (string, error) {
	spec, err := GetEncodingSpec(name)
	if err != nil {
		return "", err
	}

	dir := CacheDir()
	localPath := filepath.Join(dir, name+".tiktoken")

	cacheMu.Lock()
	defer cacheMu.Unlock()

	if _, err := os.Stat(localPath); err == nil {
		return localPath, nil
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("turbotoken: create cache dir: %w", err)
	}

	resp, err := http.Get(spec.RankFileURL)
	if err != nil {
		return "", downloadError(spec.RankFileURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", downloadError(spec.RankFileURL, fmt.Errorf("HTTP %d", resp.StatusCode))
	}

	tmp := localPath + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return "", fmt.Errorf("turbotoken: create temp file: %w", err)
	}

	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		os.Remove(tmp)
		return "", downloadError(spec.RankFileURL, err)
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return "", fmt.Errorf("turbotoken: close temp file: %w", err)
	}

	if err := os.Rename(tmp, localPath); err != nil {
		os.Remove(tmp)
		return "", fmt.Errorf("turbotoken: rename rank file: %w", err)
	}

	return localPath, nil
}

// ReadRankFile reads the rank file bytes for the given encoding,
// downloading the file first if it does not exist locally.
func ReadRankFile(name string) ([]byte, error) {
	path, err := EnsureRankFile(name)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("turbotoken: read rank file: %w", err)
	}
	return data, nil
}
