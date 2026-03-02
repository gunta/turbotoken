package com.turbotoken;

/**
 * Exception thrown by turbotoken native operations.
 */
public class TurboTokenException extends RuntimeException {

    public TurboTokenException(String message) {
        super(message);
    }

    public TurboTokenException(String message, Throwable cause) {
        super(message, cause);
    }
}
