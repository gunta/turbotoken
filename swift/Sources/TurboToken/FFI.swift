import CTurboToken
import Foundation

/// Two-pass allocation helper: first call with nil to get size, then allocate and fill.
@inlinable
internal func callTwoPass<T>(
    sizeQuery: () -> Int,
    fill: (UnsafeMutablePointer<T>, Int) -> Int
) throws -> [T] {
    let count = sizeQuery()
    guard count >= 0 else {
        throw TurboTokenError.encodingFailed("FFI size query returned error code \(count)")
    }
    if count == 0 { return [] }
    var buffer = [T](repeating: T.self == UInt32.self ? unsafeBitCast(UInt32(0), to: T.self) : unsafeBitCast(UInt8(0), to: T.self), count: count)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
        fill(ptr.baseAddress!, ptr.count)
    }
    guard written >= 0 else {
        throw TurboTokenError.encodingFailed("FFI fill returned error code \(written)")
    }
    if written < count {
        buffer.removeSubrange(written..<count)
    }
    return buffer
}

/// Two-pass allocation for UInt32 output (tokens).
internal func callTwoPassUInt32(
    sizeQuery: () -> Int,
    fill: (UnsafeMutablePointer<UInt32>, Int) -> Int
) throws -> [UInt32] {
    let count = sizeQuery()
    guard count >= 0 else {
        throw TurboTokenError.encodingFailed("FFI size query returned error code \(count)")
    }
    if count == 0 { return [] }
    var buffer = [UInt32](repeating: 0, count: count)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
        fill(ptr.baseAddress!, ptr.count)
    }
    guard written >= 0 else {
        throw TurboTokenError.encodingFailed("FFI fill returned error code \(written)")
    }
    if written < count {
        buffer.removeSubrange(written..<count)
    }
    return buffer
}

/// Two-pass allocation for UInt8 output (decoded bytes).
internal func callTwoPassUInt8(
    sizeQuery: () -> Int,
    fill: (UnsafeMutablePointer<UInt8>, Int) -> Int
) throws -> [UInt8] {
    let count = sizeQuery()
    guard count >= 0 else {
        throw TurboTokenError.decodingFailed("FFI size query returned error code \(count)")
    }
    if count == 0 { return [] }
    var buffer = [UInt8](repeating: 0, count: count)
    let written = buffer.withUnsafeMutableBufferPointer { ptr in
        fill(ptr.baseAddress!, ptr.count)
    }
    guard written >= 0 else {
        throw TurboTokenError.decodingFailed("FFI fill returned error code \(written)")
    }
    if written < count {
        buffer.removeSubrange(written..<count)
    }
    return buffer
}

/// Get turbotoken version string.
internal func ffiVersion() -> String {
    guard let cStr = turbotoken_version() else { return "unknown" }
    return String(cString: cStr)
}

/// Clear the internal rank table cache.
internal func ffiClearCache() {
    turbotoken_clear_rank_table_cache()
}
