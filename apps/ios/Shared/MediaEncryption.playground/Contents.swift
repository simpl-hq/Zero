import UIKit
import Zero

hs_init(0, nil)

let totalBytes = 20
let ivTagBytes = 28
var base: UnsafeMutableRawPointer = malloc(totalBytes)

let assume = base.assumingMemoryBound(to: UInt8.self)
assume[0] = 0
for i in 1..<totalBytes {
    assume[i] = UInt8(i)
}
let unencrypted = NSData(bytesNoCopy: base, length: totalBytes)
let aesKey = "PI-bV-FTgRqZM_lsDH9T21a0yRVMsvLFmvilJ9Ssk3g="

if var key: [CChar] = aesKey.cString(using: .utf8),
   let pointer: UnsafeMutableRawPointer = malloc(unencrypted.count + ivTagBytes) {
    debugPrint("AesKey \(aesKey), cString \(key)")
    memcpy(pointer, (unencrypted as NSData).bytes, unencrypted.count)
    let source_ = Data(bytes: pointer, count: unencrypted.count)
    let isKeyFrame = unencrypted[0] & 1 == 0
    debugPrint("Is key frame \(isKeyFrame)")
    let clearTextBytesSize = isKeyFrame ? 10 : 3
    for i in 0..<48 {
        debugPrint("Before \(i)  \(unencrypted[i])")
    }
    if let res = zero_core_runtime_encrypt_media(&key, pointer.advanced(by: clearTextBytesSize), Int32(unencrypted.count + ivTagBytes - clearTextBytesSize)) {
        printError("encrypt", res)
    }
    for i in 0..<48 {
        debugPrint("After \(i)  \(pointer.assumingMemoryBound(to: UInt8.self)[i])")
    }
    let res_ = Data(bytes: pointer, count: unencrypted.count + ivTagBytes)
    print(source_ == res_)

    if let res = zero_core_runtime_decrypt_media(&key, pointer.advanced(by: clearTextBytesSize), Int32(unencrypted.count + ivTagBytes - clearTextBytesSize)) {
        printError("decrypt", res)
    }

    let decrypted_ = Data(bytes: pointer, count: unencrypted.count)
    for i in 0..<48 {
        debugPrint("After decrypt \(i)  \(pointer.assumingMemoryBound(to: UInt8.self)[i])")
    }
    print(source_ == decrypted_)
}

func printError(_ op: String, _ res: UnsafeMutablePointer<CChar>) {
    let err = fromCString(res)
    if err == "" {
        print("\(op) ok")
    } else {
        print("\(op) error: \(err)")
    }
}
