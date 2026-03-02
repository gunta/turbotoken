// Package turbotoken provides Go bindings for turbotoken, the fastest BPE tokenizer.
package turbotoken

import (
	"errors"
	"fmt"
)

// Sentinel errors for turbotoken operations.
var (
	ErrNative          = errors.New("turbotoken: native library error")
	ErrInvalidEncoding = errors.New("turbotoken: invalid encoding name")
	ErrDownload        = errors.New("turbotoken: rank file download failed")
)

// TurbotokenError wraps errors from turbotoken operations with additional context.
type TurbotokenError struct {
	Op  string // operation that failed
	Err error  // underlying error
}

func (e *TurbotokenError) Error() string {
	return fmt.Sprintf("turbotoken: %s: %v", e.Op, e.Err)
}

func (e *TurbotokenError) Unwrap() error {
	return e.Err
}

func nativeError(op string) error {
	return &TurbotokenError{Op: op, Err: ErrNative}
}

func encodingError(name string) error {
	return &TurbotokenError{
		Op:  "get_encoding",
		Err: fmt.Errorf("%w: %q", ErrInvalidEncoding, name),
	}
}

func downloadError(url string, err error) error {
	return &TurbotokenError{
		Op:  "download",
		Err: fmt.Errorf("%w: %s: %v", ErrDownload, url, err),
	}
}
