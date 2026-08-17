import SwiftUI
import CryptoKit
import Zero

private enum Argon2idPow {
    private static let blake2bIV: [UInt64] = [
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
        0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f,
        0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
    ]

    private static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3]
    ]

    @inline(__always)
    private static func rotr64(_ x: UInt64, _ n: UInt64) -> UInt64 {
        (x >> n) | (x << (64 - n))
    }

    private static func load64LE(_ b: [UInt8], _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(b[off + i]) << (8 * i)
        }
        return v
    }

    private static func appendLE32(_ dst: inout [UInt8], _ v: UInt32) {
        dst.append(UInt8(v & 0xFF))
        dst.append(UInt8((v >> 8) & 0xFF))
        dst.append(UInt8((v >> 16) & 0xFF))
        dst.append(UInt8((v >> 24) & 0xFF))
    }

    static func blake2b(_ input: [UInt8], outLen: Int) -> [UInt8] {
        var h = blake2bIV
        h[0] ^= (0x01010000 | UInt64(outLen))

        var m = [UInt64](repeating: 0, count: 16)
        var v = [UInt64](repeating: 0, count: 16)
        var block = [UInt8](repeating: 0, count: 128)
        var offset = 0
        var compressed: UInt64 = 0

        func compress(last: Bool) {
            for i in 0..<16 { m[i] = load64LE(block, i * 8) }
            for i in 0..<8 {
                v[i] = h[i]
                v[i + 8] = blake2bIV[i]
            }
            v[12] ^= compressed
            if last { v[14] = ~v[14] }

            func gB(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt64, _ y: UInt64) {
                v[a] = v[a] &+ v[b] &+ x
                v[d] = rotr64(v[d] ^ v[a], 32)
                v[c] = v[c] &+ v[d]
                v[b] = rotr64(v[b] ^ v[c], 24)
                v[a] = v[a] &+ v[b] &+ y
                v[d] = rotr64(v[d] ^ v[a], 16)
                v[c] = v[c] &+ v[d]
                v[b] = rotr64(v[b] ^ v[c], 63)
            }

            for r in 0..<12 {
                let s = sigma[r]
                gB(0, 4, 8, 12, m[s[0]], m[s[1]])
                gB(1, 5, 9, 13, m[s[2]], m[s[3]])
                gB(2, 6, 10, 14, m[s[4]], m[s[5]])
                gB(3, 7, 11, 15, m[s[6]], m[s[7]])
                gB(0, 5, 10, 15, m[s[8]], m[s[9]])
                gB(1, 6, 11, 12, m[s[10]], m[s[11]])
                gB(2, 7, 8, 13, m[s[12]], m[s[13]])
                gB(3, 4, 9, 14, m[s[14]], m[s[15]])
            }
            for i in 0..<8 { h[i] ^= v[i] ^ v[i + 8] }
        }

        let total = input.count
        if total == 0 {
            compress(last: true)
        } else {
            while offset + 128 < total {
                block.replaceSubrange(0..<128, with: input[offset..<(offset + 128)])
                compressed &+= 128
                compress(last: false)
                offset += 128
            }
            let rem = total - offset
            block = [UInt8](repeating: 0, count: 128)
            block.replaceSubrange(0..<rem, with: input[offset..<total])
            compressed &+= UInt64(rem)
            compress(last: true)
        }

        var out = [UInt8](repeating: 0, count: outLen)
        for i in 0..<outLen {
            out[i] = UInt8((h[i / 8] >> (8 * (i % 8))) & 0xFF)
        }
        return out
    }

    private static func blake2bLong(_ outLen: Int, _ data: [UInt8]) -> [UInt8] {
        var prefixed: [UInt8] = []
        prefixed.reserveCapacity(4 + data.count)
        appendLE32(&prefixed, UInt32(outLen))
        prefixed.append(contentsOf: data)
        if outLen <= 64 { return blake2b(prefixed, outLen: outLen) }

        var out = [UInt8]()
        out.reserveCapacity(outLen)
        var v = blake2b(prefixed, outLen: 64)
        out.append(contentsOf: v[0..<32])
        var rem = outLen - 32
        while rem > 64 {
            v = blake2b(v, outLen: 64)
            out.append(contentsOf: v[0..<32])
            rem -= 32
        }
        out.append(contentsOf: blake2b(v, outLen: rem))
        return out
    }

    @inline(__always)
    private static func gArgon(_ z: inout [UInt64], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        var va = z[a], vb = z[b], vc = z[c], vd = z[d]
        va = va &+ vb &+ 2 &* (va & 0xFFFFFFFF) &* (vb & 0xFFFFFFFF)
        vd = rotr64(vd ^ va, 32)
        vc = vc &+ vd &+ 2 &* (vc & 0xFFFFFFFF) &* (vd & 0xFFFFFFFF)
        vb = rotr64(vb ^ vc, 24)
        va = va &+ vb &+ 2 &* (va & 0xFFFFFFFF) &* (vb & 0xFFFFFFFF)
        vd = rotr64(vd ^ va, 16)
        vc = vc &+ vd &+ 2 &* (vc & 0xFFFFFFFF) &* (vd & 0xFFFFFFFF)
        vb = rotr64(vb ^ vc, 63)
        z[a] = va; z[b] = vb; z[c] = vc; z[d] = vd
    }

    private static func pStep(_ z: inout [UInt64], _ idx: [Int]) {
        gArgon(&z, idx[0], idx[4], idx[8], idx[12])
        gArgon(&z, idx[1], idx[5], idx[9], idx[13])
        gArgon(&z, idx[2], idx[6], idx[10], idx[14])
        gArgon(&z, idx[3], idx[7], idx[11], idx[15])
        gArgon(&z, idx[0], idx[5], idx[10], idx[15])
        gArgon(&z, idx[1], idx[6], idx[11], idx[12])
        gArgon(&z, idx[2], idx[7], idx[8], idx[13])
        gArgon(&z, idx[3], idx[4], idx[9], idx[14])
    }

    private static func compressBlocks(_ x: [UInt64], _ y: [UInt64]) -> [UInt64] {
        var r = [UInt64](repeating: 0, count: 128)
        var z = [UInt64](repeating: 0, count: 128)
        for i in 0..<128 {
            let v = x[i] ^ y[i]
            r[i] = v
            z[i] = v
        }
        for i in 0..<8 {
            let b = 16 * i
            pStep(&z, Array(b..<(b + 16)))
        }
        for i in 0..<8 {
            let c = 2 * i
            pStep(&z, [
                c, c + 1, 16 + c, 16 + c + 1, 32 + c, 32 + c + 1, 48 + c, 48 + c + 1,
                64 + c, 64 + c + 1, 80 + c, 80 + c + 1, 96 + c, 96 + c + 1, 112 + c, 112 + c + 1
            ])
        }
        var out = [UInt64](repeating: 0, count: 128)
        for i in 0..<128 { out[i] = r[i] ^ z[i] }
        return out
    }

    private static func bytesToBlock(_ b: [UInt8]) -> [UInt64] {
        var block = [UInt64](repeating: 0, count: 128)
        for i in 0..<128 { block[i] = load64LE(b, i * 8) }
        return block
    }

    static func hash(secret: [UInt8], salt: [UInt8], memoryCost: Int = 8192, timeCost: Int = 1, outLen: Int = 32) -> [UInt8] {
        var h0In: [UInt8] = []
        appendLE32(&h0In, 1)
        appendLE32(&h0In, UInt32(outLen))
        appendLE32(&h0In, UInt32(memoryCost))
        appendLE32(&h0In, UInt32(timeCost))
        appendLE32(&h0In, 0x13)
        appendLE32(&h0In, 2)
        appendLE32(&h0In, UInt32(secret.count))
        h0In.append(contentsOf: secret)
        appendLE32(&h0In, UInt32(salt.count))
        h0In.append(contentsOf: salt)
        appendLE32(&h0In, 0)
        appendLE32(&h0In, 0)

        let h0 = blake2b(h0In, outLen: 64)
        var blocks = [[UInt64]](repeating: [], count: memoryCost)
        var seed0 = h0
        appendLE32(&seed0, 0)
        appendLE32(&seed0, 0)
        blocks[0] = bytesToBlock(blake2bLong(1024, seed0))

        var seed1 = h0
        appendLE32(&seed1, 1)
        appendLE32(&seed1, 0)
        blocks[1] = bytesToBlock(blake2bLong(1024, seed1))

        let sl = memoryCost / 4
        let zeroBlock = [UInt64](repeating: 0, count: 128)
        var addrInput = [UInt64](repeating: 0, count: 128)
        var addrBlock = zeroBlock
        var prevSlice = -1
        var addrCounter: UInt64 = 0

        for i in 2..<memoryCost {
            let slice = i / sl
            let idxInSlice = i % sl
            let j1: UInt64
            if slice < 2 {
                if slice != prevSlice {
                    prevSlice = slice
                    addrCounter = 0
                }
                if idxInSlice % 128 == 0 || i == 2 {
                    addrCounter += 1
                    addrInput = [UInt64](repeating: 0, count: 128)
                    addrInput[2] = UInt64(slice)
                    addrInput[3] = UInt64(memoryCost)
                    addrInput[4] = UInt64(timeCost)
                    addrInput[5] = 2
                    addrInput[6] = addrCounter
                    let tmp = compressBlocks(zeroBlock, addrInput)
                    addrBlock = compressBlocks(zeroBlock, tmp)
                }
                j1 = addrBlock[idxInSlice % 128] & 0xFFFFFFFF
            } else {
                j1 = blocks[i - 1][0] & 0xFFFFFFFF
            }

            let refArea = UInt64(i - 1)
            var rel = (j1 &* j1) >> 32
            rel = refArea - 1 - ((refArea &* rel) >> 32)
            blocks[i] = compressBlocks(blocks[i - 1], blocks[Int(rel)])
        }

        var lastBytes = [UInt8]()
        lastBytes.reserveCapacity(1024)
        for w in blocks[memoryCost - 1] {
            for shift in 0..<8 {
                lastBytes.append(UInt8((w >> (8 * shift)) & 0xFF))
            }
        }
        return blake2bLong(outLen, lastBytes)
    }
}

struct ZeroPhraseIdentity {
    let phrase: String
    let deepLink: String
    let slug: String
}

final class ZeroIdentityBridge {
    static let shared = ZeroIdentityBridge()

    private let primaryDirectoryUrl = "https://zeroapi.simpl.global"
    static let deepLinkPrefix = "https://simpl.global/add/"
    private let argon2Salt = Array("zero-argon2id-pow".utf8)
    private let maxIterations: UInt64 = 50_000
    private let phraseDefaultsKey = "app.zero.account.phrase"
    private let deepLinkDefaultsKey = "app.zero.account.deeplink"
    private let cacheDefaultsKey = "app.zero.account.identity_cache"

    private static let fallbackWords = [
        "Acorn", "Amber", "Anchor", "Apex", "Arbor", "Arctic", "Arrow", "Aspen",
        "Atlas", "Aurora", "Azure", "Beacon", "Birch", "Blaze", "Boulder", "Breeze",
        "Bridge", "Brook", "Canyon", "Carbon", "Cedar", "Cipher", "Cloud", "Cobalt",
        "Comet", "Copper", "Coral", "Cosmos", "Crest", "Crimson", "Crystal", "Cypress",
        "Dawn", "Delta", "Diamond", "Drift", "Dune", "Echo", "Eclipse", "Ember",
        "Emerald", "Falcon", "Feather", "Fjord", "Flame", "Flint", "Forest", "Forge",
        "Frost", "Galaxy", "Garnet", "Glacier", "Glade", "Granite", "Harbor", "Hawk",
        "Heather", "Helix", "Horizon", "Indigo", "Iron", "Island", "Ivory", "Jade",
        "Jasper", "Juniper", "Kestrel", "Lagoon", "Lantern", "Laurel", "Lotus", "Lunar",
        "Lynx", "Magnet", "Maple", "Marble", "Meadow", "Mercury", "Meteor", "Mirror",
        "Mist", "Monarch", "Moon", "Nebula", "Nimbus", "Noble", "North", "Nova",
        "Oak", "Oasis", "Obsidian", "Ocean", "Onyx", "Opal", "Orbit", "Orchid",
        "Osprey", "Otter", "Ozone", "Panther", "Pebble", "Phantom", "Phoenix", "Pine",
        "Planet", "Polar", "Prism", "Quartz", "Quill", "Rain", "Raven", "Redwood",
        "Reef", "Ridge", "Ripple", "River", "Rocket", "Ruby", "Sable", "Saffron",
        "Sage", "Sapphire", "Scarlet", "Sequoia", "Shadow", "Shield", "Sierra", "Silver",
        "Slate", "Snow", "Solar", "Solstice", "Spark", "Specter", "Sphere", "Spruce",
        "Star", "Steel", "Stone", "Storm", "Summit", "Swift", "Tempest", "Thunder",
        "Timber", "Topaz", "Torch", "Trail", "Tundra", "Valiant", "Valley", "Vapor",
        "Vector", "Velvet", "Vertex", "Vesper", "Vortex", "Voyager", "Wave", "Whisper",
        "Willow", "Winter", "Wolf", "Zenith", "Zephyr"
    ]

    var currentPhrase: String? {
        get { UserDefaults.standard.string(forKey: phraseDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: phraseDefaultsKey) }
    }

    var currentDeepLink: String? {
        get { UserDefaults.standard.string(forKey: deepLinkDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: deepLinkDefaultsKey) }
    }

    static func normalizePhrase(_ raw: String) -> String {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace || $0 == "-" }
            .map { $0.lowercased().capitalized }
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLetter) }) else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parts.joined(separator: "-")
    }

    static func isValid4WordPhrase(_ raw: String) -> Bool {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace || $0 == "-" }
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isLetter) }
    }

    static func extractResolveTarget(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix(deepLinkPrefix) {
            return String(trimmed.dropFirst(deepLinkPrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 6 {
            let d = Array(digits)
            return String(d[0..<3]) + "-" + String(d[3..<6])
        }
        if isValid4WordPhrase(trimmed) {
            return trimmed.split { $0.isWhitespace || $0 == "-" }.map { $0.lowercased() }.joined(separator: "-")
        }
        return trimmed
    }

    func solveArgon2idPuzzle(ip: String, time: Int64) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [argon2Salt, maxIterations] in
            var nonce: UInt64 = 0
            while nonce < maxIterations {
                try Task.checkCancellation()
                let secret = Array("\(ip):\(time):\(nonce)".utf8)
                let digest = Argon2idPow.hash(secret: secret, salt: argon2Salt)
                if (digest[0] & 0xF0) == 0 {
                    return String(nonce)
                }
                nonce += 1
            }
            throw NSError(domain: "ZeroIdentityBridge", code: 408, userInfo: [NSLocalizedDescriptionKey: "Argon2id PoW solver timeout"])
        }.value
    }

    func provisionPhraseAndDeepLink(localCryptoInviteUrl: String, dummyIp: String = "127.0.0.1") async throws -> ZeroPhraseIdentity {
        let trimmedInvite = localCryptoInviteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInvite = trimmedInvite.isEmpty ? "zero:/contact" : trimmedInvite
        let timestamp = Int64(Date().timeIntervalSince1970)
        let verifiedNonce = try await solveArgon2idPuzzle(ip: dummyIp, time: timestamp)

        let bodyData = try JSONSerialization.data(withJSONObject: [
            "invite_url": effectiveInvite,
            "nonce": verifiedNonce,
            "timestamp": timestamp
        ])

        for base in [primaryDirectoryUrl] {
            guard let url = URL(string: "\(base)/api/v1/identity/phrase") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8.0)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("ZeroCore/1.0", forHTTPHeaderField: "User-Agent")
            req.httpBody = bodyData
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let phrase = json["phrase"] as? String,
                   let deepLink = json["deep_link"] as? String,
                   let slug = json["slug"] as? String {
                    let normalized = Self.normalizePhrase(phrase)
                    cacheIdentityMapping(key: normalized, inviteUrl: effectiveInvite)
                    currentPhrase = normalized
                    currentDeepLink = deepLink
                    return ZeroPhraseIdentity(phrase: normalized, deepLink: deepLink, slug: slug)
                }
            } catch {
                continue
            }
        }

        let fallbackPhrase = (0..<4).map { _ in Self.fallbackWords.randomElement()! }.joined(separator: "-")
        let fallbackSlug = fallbackPhrase.lowercased().replacingOccurrences(of: "-", with: "")
        let fallbackLink = "\(Self.deepLinkPrefix)\(fallbackSlug)"
        cacheIdentityMapping(key: fallbackPhrase, inviteUrl: effectiveInvite)
        currentPhrase = fallbackPhrase
        currentDeepLink = fallbackLink
        return ZeroPhraseIdentity(phrase: fallbackPhrase, deepLink: fallbackLink, slug: fallbackSlug)
    }

    func provisionEphemeral6DigitCode(localCryptoInviteUrl: String, dummyIp: String = "127.0.0.1") async throws -> String {
        let trimmedInvite = localCryptoInviteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInvite = trimmedInvite.isEmpty ? "zero:/contact" : trimmedInvite
        let timestamp = Int64(Date().timeIntervalSince1970)
        let verifiedNonce = try await solveArgon2idPuzzle(ip: dummyIp, time: timestamp)

        let bodyData = try JSONSerialization.data(withJSONObject: [
            "invite_url": effectiveInvite,
            "nonce": verifiedNonce,
            "timestamp": timestamp
        ])

        for base in [primaryDirectoryUrl] {
            guard let url = URL(string: "\(base)/api/v1/identity/ephemeral") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8.0)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("ZeroCore/1.0", forHTTPHeaderField: "User-Agent")
            req.httpBody = bodyData
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let code = json["code"] as? String {
                    cacheIdentityMapping(key: code, inviteUrl: effectiveInvite)
                    return code
                }
            } catch {
                continue
            }
        }

        let p1 = Int.random(in: 100...999)
        let p2 = Int.random(in: 100...999)
        let localCode = String(format: "%03d-%03d", p1, p2)
        cacheIdentityMapping(key: localCode, inviteUrl: effectiveInvite)
        return localCode
    }

    func resolveIdentity(rawTarget: String) async throws -> String {
        let target = Self.extractResolveTarget(rawTarget)
        for base in [primaryDirectoryUrl] {
            guard let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "\(base)/api/v1/identity/resolve/\(encoded)") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8.0)
            req.httpMethod = "GET"
            req.setValue("ZeroCore/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let inviteUrl = json["invite_url"] as? String,
                   !inviteUrl.isEmpty {
                    cacheIdentityMapping(key: target, inviteUrl: inviteUrl)
                    return inviteUrl
                }
            } catch {
                continue
            }
        }

        if let cached = lookupCachedIdentity(key: target) {
            return cached
        }
        throw NSError(domain: "ZeroIdentityBridge", code: 404, userInfo: [NSLocalizedDescriptionKey: "Identity not found or expired"])
    }

    func cacheIdentityMapping(key: String, inviteUrl: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: cacheDefaultsKey) as? [String: String]) ?? [:]
        dict[key] = inviteUrl
        UserDefaults.standard.set(dict, forKey: cacheDefaultsKey)
    }

    func lookupCachedIdentity(key: String) -> String? {
        let dict = (UserDefaults.standard.dictionary(forKey: cacheDefaultsKey) as? [String: String]) ?? [:]
        return dict[key]
    }
}

@MainActor
func provisionSilentZeroAccount(existingPhrase: String? = nil, completeOnboarding: Bool = true) async throws -> String {
    let m = ChatModel.shared
    if m.currentUser == nil {
        AppChatState.shared.set(.active)
        let suffix = Int.random(in: 1000...9999)
        let profile = Profile(displayName: "Zero-\(suffix)", fullName: "", shortDescr: nil, image: nil)
        m.currentUser = try apiCreateActiveUser(profile)
        if m.users.isEmpty || m.users.allSatisfy({ $0.user.hidden }) {
            try? startChat()
        }
    }

    let conditionsId = m.conditions.currentConditions.conditionsId
    let allOpIds = m.conditions.serverOperators.map { $0.operatorId }
    if !allOpIds.isEmpty {
        if let updated = try? await acceptConditions(conditionsId: conditionsId, operatorIds: allOpIds) {
            m.conditions = updated
        }
    }

    var inviteUri = m.userAddress?.connLinkContact.connFullLink ?? ""
    if inviteUri.isEmpty {
        if let created = try? await apiCreateUserAddress() {
            m.userAddress = UserContactLink(created)
            inviteUri = created.connFullLink
        }
    }

    let phrase: String
    if let provided = existingPhrase, ZeroIdentityBridge.isValid4WordPhrase(provided) {
        let normalized = ZeroIdentityBridge.normalizePhrase(provided)
        ZeroIdentityBridge.shared.currentPhrase = normalized
        phrase = normalized
    } else if let existing = ZeroIdentityBridge.shared.currentPhrase, ZeroIdentityBridge.isValid4WordPhrase(existing) {
        phrase = existing
    } else {
        let res = try await ZeroIdentityBridge.shared.provisionPhraseAndDeepLink(localCryptoInviteUrl: inviteUri)
        phrase = res.phrase
    }

    if completeOnboarding {
        onboardingStageDefault.set(.onboardingComplete)
        m.onboardingStage = .onboardingComplete
    }
    return phrase
}

struct ZeroInfo: View {
    @EnvironmentObject var m: ChatModel
    @EnvironmentObject var theme: AppTheme
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @State private var isProvisioning = false
    @State private var provisioningStatus = "Securing your Zero identity (Argon2id)..."
    @State private var createdPhrase: String? = nil
    @State private var copiedCreatedPhrase = false
    @State private var showGuidedTutorial = false
    @State private var showExistingPhraseSheet = false
    @State private var existingPhraseInput = ""
    @State private var errorMessage: String? = nil
    var onboarding: Bool

    var body: some View {
        GeometryReader { g in
            if onboarding {
                minimalistAppleOnboarding(g)
            } else {
                aboutZeroView(g)
            }
        }
        .onAppear {
            setLastVersionDefault()
        }
        .frame(maxHeight: .infinity)
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func minimalistAppleOnboarding(_ g: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("Zero")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(theme.colors.onBackground)

                Text("Private messaging, made simple.\nNo phone number. No email. Nothing that identifies you.")
                    .font(.subheadline)
                    .foregroundColor(theme.colors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            if isProvisioning {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.25)
                    Text(provisioningStatus)
                        .font(.footnote)
                        .foregroundColor(theme.colors.secondary)
                }
                .padding(.bottom, 48)
            } else if let createdPhrase {
                VStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = createdPhrase
                        copiedCreatedPhrase = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            copiedCreatedPhrase = false
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(copiedCreatedPhrase ? "4-WORD PHRASE COPIED" : "YOUR 4-WORD PHRASE")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(copiedCreatedPhrase ? theme.colors.primary : theme.colors.secondary)
                            Text(createdPhrase)
                                .font(.system(size: 19, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.colors.onBackground)
                                .multilineTextAlignment(.center)
                            Label("Tap to copy", systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(theme.colors.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        showGuidedTutorial = true
                    } label: {
                        Text("Start Quick Setup Guide")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(theme.colors.primary)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        finishZeroOnboarding()
                    } label: {
                        Text("Skip to Zero")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(theme.colors.secondary)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            } else {
                VStack(spacing: 16) {
                    Button {
                        createZeroIdentity()
                    } label: {
                        Text("Create Zero Identity")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(theme.colors.primary)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        existingPhraseInput = ""
                        errorMessage = nil
                        showExistingPhraseSheet = true
                    } label: {
                        Text("I Already Have a Phrase")
                            .font(.headline)
                            .foregroundColor(theme.colors.onBackground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(theme.colors.secondary.opacity(0.35), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 400)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, minHeight: g.size.height)
        .sheet(isPresented: $showGuidedTutorial) {
            ZeroGuidedTutorialView(allowSettingsShortcuts: false) {
                showGuidedTutorial = false
                finishZeroOnboarding()
            }
            .environmentObject(m)
            .environmentObject(theme)
        }
        .sheet(isPresented: $showExistingPhraseSheet) {
            existingPhraseSheetView
        }
        .sheet(isPresented: Binding(
            get: { m.migrationState != nil && !showExistingPhraseSheet },
            set: { _ in
                m.migrationState = nil
                MigrationToDeviceState.save(nil) }
        )) {
            NavigationView {
                VStack(alignment: .leading) {
                    MigrateToDevice(migrationState: $m.migrationState)
                }
                .navigationTitle("Migrate here")
                .modifier(ThemedBackground(grouped: true))
            }
        }
    }

    private var existingPhraseSheetView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Enter Your 4-Word Zero Phrase")
                    .font(.title3)
                    .bold()
                    .padding(.top, 24)

                Text("Example: Crimson-Velvet-Horizon-Echo")
                    .font(.footnote)
                    .foregroundColor(theme.colors.secondary)

                TextField("Crimson-Velvet-Horizon-Echo", text: $existingPhraseInput)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }

                Button {
                    restoreWithPhrase()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(ZeroIdentityBridge.isValid4WordPhrase(existingPhraseInput) ? theme.colors.primary : Color.gray.opacity(0.4))
                        )
                }
                .disabled(!ZeroIdentityBridge.isValid4WordPhrase(existingPhraseInput))
                .padding(.horizontal, 24)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showExistingPhraseSheet = false
                    }
                }
            }
        }
    }

    private func createZeroIdentity() {
        isProvisioning = true
        errorMessage = nil
        provisioningStatus = "Securing your Zero identity (Argon2id)..."
        Task {
            do {
                let phrase = try await provisionSilentZeroAccount(existingPhrase: nil, completeOnboarding: false)
                await MainActor.run {
                    createdPhrase = phrase
                    isProvisioning = false
                }
            } catch {
                await MainActor.run {
                    isProvisioning = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // mark onboarding complete once user finishes or skips guide
    private func finishZeroOnboarding() {
        onboardingStageDefault.set(.onboardingComplete)
        m.onboardingStage = .onboardingComplete
    }

    private func restoreWithPhrase() {
        let normalized = ZeroIdentityBridge.normalizePhrase(existingPhraseInput)
        guard ZeroIdentityBridge.isValid4WordPhrase(normalized) else {
            errorMessage = "Enter a valid 4-word phrase (e.g. Crimson-Velvet-Horizon-Echo)."
            return
        }
        showExistingPhraseSheet = false
        isProvisioning = true
        errorMessage = nil
        provisioningStatus = "Verifying 4-word phrase..."
        Task {
            do {
                _ = try await ZeroIdentityBridge.shared.resolveIdentity(rawTarget: normalized)
                await MainActor.run {
                    ZeroIdentityBridge.shared.currentPhrase = normalized
                    isProvisioning = false
                    if m.migrationState == nil {
                        m.migrationState = .pasteOrScanLink
                    }
                }
            } catch {
                await MainActor.run {
                    isProvisioning = false
                    errorMessage = "We couldn't find that 4-word phrase. Check it and try again."
                }
            }
        }
    }

    @ViewBuilder
    private func aboutZeroView(_ g: GeometryProxy) -> some View {
        VStack(alignment: .center, spacing: 14) {
            Text("Zero")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .padding(.top, 32)

            Text("Privacy Should Be Effortless.")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Post-quantum Double Ratchet encryption over unidirectional queues, 2-hop private onion routing, XFTP media transfers, and local SQLCipher storage.")
                .font(.footnote)
                .foregroundColor(theme.colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let phrase = ZeroIdentityBridge.shared.currentPhrase {
                VStack(spacing: 6) {
                    Text("Your 4-Word Zero Phrase")
                        .font(.caption)
                        .foregroundColor(theme.colors.secondary)
                    Text(phrase)
                        .font(.system(.headline, design: .monospaced).weight(.bold))
                        .foregroundColor(theme.colors.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.top, 12)
            }

            Button {
                showGuidedTutorial = true
            } label: {
                Label("Start Quick Setup Guide", systemImage: "book.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 320)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.colors.primary)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 25)
        .frame(minHeight: g.size.height)
        .sheet(isPresented: $showGuidedTutorial) {
            ZeroGuidedTutorialView(allowSettingsShortcuts: true) {
                showGuidedTutorial = false
            }
            .environmentObject(m)
            .environmentObject(theme)
        }
    }
}

let textSpace = Text(verbatim: " ")

let textNewLine = Text(verbatim: "\n")

struct ZeroInfo_Previews: PreviewProvider {
    static var previews: some View {
        ZeroInfo(onboarding: true)
    }
}
