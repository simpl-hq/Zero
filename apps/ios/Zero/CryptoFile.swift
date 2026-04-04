import Foundation

enum WriteFileResult: Decodable {
    case result(cryptoArgs: CryptoFileArgs)
    case error(writeError: String)
}

public func writeCryptoFile(path: String, data: Data) throws -> CryptoFileArgs {
    let ptr: UnsafeMutableRawPointer = malloc(data.count)
    memcpy(ptr, (data as NSData).bytes, data.count)
    var cPath = path.cString(using: .utf8)!
    let cjson = zero_core_runtime_write_file(getChatCtrl(), &cPath, ptr, Int32(data.count))!
    let d = dataFromCString(cjson)!
    switch try jsonDecoder.decode(WriteFileResult.self, from: d) {
    case let .result(cfArgs): return cfArgs
    case let .error(err): throw RuntimeError(err)
    }
}

public func readCryptoFile(path: String, cryptoArgs: CryptoFileArgs) throws -> Data {
    var cPath = path.cString(using: .utf8)!
    var cKey = cryptoArgs.fileKey.cString(using: .utf8)!
    var cNonce = cryptoArgs.fileNonce.cString(using: .utf8)!
    let ptr = zero_core_runtime_read_file(&cPath, &cKey, &cNonce)!
    let status = UInt8(ptr.pointee)
    switch status {
    case 0:
        let dLen = Data(bytes: ptr.advanced(by: 1), count: 4)
        let len = dLen.withUnsafeBytes { $0.load(as: UInt32.self) }
        let d = Data(bytes: ptr.advanced(by: 5), count: Int(len))
        free(ptr)
        return d
    case 1:
        let err = String.init(cString: ptr)
        free(ptr)
        throw RuntimeError(err)
    default:
        throw RuntimeError("unexpected zero_core_runtime_read_file status: \(status)")
    }
}

public func encryptCryptoFile(fromPath: String, toPath: String) throws -> CryptoFileArgs {
    var cFromPath = fromPath.cString(using: .utf8)!
    var cToPath = toPath.cString(using: .utf8)!
    let cjson = zero_core_runtime_encrypt_file(getChatCtrl(), &cFromPath, &cToPath)!
    let d = dataFromCString(cjson)!
    switch try jsonDecoder.decode(WriteFileResult.self, from: d) {
    case let .result(cfArgs): return cfArgs
    case let .error(err): throw RuntimeError(err)
    }
}

public func decryptCryptoFile(fromPath: String, cryptoArgs: CryptoFileArgs, toPath: String) throws {
    var cFromPath = fromPath.cString(using: .utf8)!
    var cKey = cryptoArgs.fileKey.cString(using: .utf8)!
    var cNonce = cryptoArgs.fileNonce.cString(using: .utf8)!
    var cToPath = toPath.cString(using: .utf8)!
    let cErr = zero_core_runtime_decrypt_file(&cFromPath, &cKey, &cNonce, &cToPath)!
    let err = fromCString(cErr)
    if err != "" { throw RuntimeError(err) }
}
