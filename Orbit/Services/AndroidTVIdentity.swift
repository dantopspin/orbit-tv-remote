import Foundation
import Security

enum AndroidTVIdentityError: LocalizedError {
    case keyGenerationFailed
    case publicKeyUnavailable
    case certificateCreationFailed
    case certificateStoreFailed(OSStatus)
    case identityUnavailable(OSStatus)
    case signatureFailed

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            return "Orbit could not create its Android TV pairing key."
        case .publicKeyUnavailable:
            return "Orbit could not read its Android TV public key."
        case .certificateCreationFailed:
            return "Orbit could not create its Android TV certificate."
        case .certificateStoreFailed(let status):
            return "Orbit could not store its Android TV certificate (\(status))."
        case .identityUnavailable(let status):
            return "Orbit could not load its Android TV identity (\(status))."
        case .signatureFailed:
            return "Orbit could not sign its Android TV certificate."
        }
    }
}

enum AndroidTVIdentityProvider {
    private static let keyTag = Data(
        "com.dantopspin.orbitremote.androidtv.identity".utf8
    )
    private static let certificateLabel = "Orbit Android TV Identity"

    static func loadOrCreateIdentity() throws -> SecIdentity {
        if let certificate = loadCertificate(),
           let identity = identity(for: certificate) {
            return identity
        }

        let privateKey = try loadOrCreatePrivateKey()
        let certificate = try makeSelfSignedCertificate(privateKey: privateKey)
        try store(certificate: certificate)

        guard let identity = identity(for: certificate) else {
            throw AndroidTVIdentityError.identityUnavailable(errSecItemNotFound)
        }

        return identity
    }

    static func publicKey(from identity: SecIdentity) throws -> SecKey {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)

        guard status == errSecSuccess,
              let certificate,
              let key = SecCertificateCopyKey(certificate) else {
            throw AndroidTVIdentityError.publicKeyUnavailable
        }

        return key
    }

    static func importedIdentityItems(
        identity: SecIdentity
    ) -> CFArray {
        [
            [
                kSecImportItemIdentity as String: identity
            ] as [String: Any]
        ] as CFArray
    }

    private static func loadOrCreatePrivateKey() throws -> SecKey {
        if let existing = loadPrivateKey() {
            return existing
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrLabel as String: certificateLabel,
                kSecAttrAccessible as String:
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(
            attributes as CFDictionary,
            &error
        ) else {
            throw error?.takeRetainedValue()
                ?? AndroidTVIdentityError.keyGenerationFailed
        }

        return key
    }

    private static func loadPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess else {
            return nil
        }

        return (result as! SecKey)
    }

    private static func loadCertificate() -> SecCertificate? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess else {
            return nil
        }

        return (result as! SecCertificate)
    }

    private static func identity(
        for certificate: SecCertificate
    ) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: certificateLabel,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard status == errSecSuccess else {
            return nil
        }

        return (result as! SecIdentity)
    }

    private static func store(
        certificate: SecCertificate
    ) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certificateLabel
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certificateLabel,
            kSecValueRef as String: certificate
        ]

        let status = SecItemAdd(
            addQuery as CFDictionary,
            nil
        )

        guard status == errSecSuccess else {
            throw AndroidTVIdentityError.certificateStoreFailed(status)
        }
    }

    private static func makeSelfSignedCertificate(
        privateKey: SecKey
    ) throws -> SecCertificate {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw AndroidTVIdentityError.publicKeyUnavailable
        }

        var exportError: Unmanaged<CFError>?
        guard let exported = SecKeyCopyExternalRepresentation(
            publicKey,
            &exportError
        ) as Data? else {
            throw exportError?.takeRetainedValue()
                ?? AndroidTVIdentityError.publicKeyUnavailable
        }

        let signatureAlgorithm = DER.sequence([
            DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]),
            DER.null()
        ])

        let rsaAlgorithm = DER.sequence([
            DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]),
            DER.null()
        ])

        let name = DER.sequence([
            DER.set([
                DER.sequence([
                    DER.oid([0x55, 0x04, 0x03]),
                    DER.utf8String("Orbit Android TV")
                ])
            ])
        ])

        let now = Date()
        let validity = DER.sequence([
            DER.utcTime(now.addingTimeInterval(-86_400)),
            DER.utcTime(
                Calendar(identifier: .gregorian)
                    .date(byAdding: .year, value: 10, to: now)
                    ?? now.addingTimeInterval(315_360_000)
            )
        ])

        let subjectPublicKeyInfo = DER.sequence([
            rsaAlgorithm,
            DER.bitString(exported)
        ])

        var serialBytes = Data(count: 8)
        let randomStatus = serialBytes.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                rawBuffer.count,
                rawBuffer.baseAddress!
            )
        }

        if randomStatus != errSecSuccess {
            serialBytes = Data([0x01])
        }

        let tbsCertificate = DER.sequence([
            DER.explicit(tag: 0, content: DER.integer(Data([0x02]))),
            DER.integer(serialBytes),
            signatureAlgorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo
        ])

        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &signError
        ) as Data? else {
            throw signError?.takeRetainedValue()
                ?? AndroidTVIdentityError.signatureFailed
        }

        let certificateData = DER.sequence([
            tbsCertificate,
            signatureAlgorithm,
            DER.bitString(signature)
        ])

        guard let certificate = SecCertificateCreateWithData(
            nil,
            certificateData as CFData
        ) else {
            throw AndroidTVIdentityError.certificateCreationFailed
        }

        return certificate
    }
}

private enum DER {
    static func sequence(_ values: [Data]) -> Data {
        tagged(0x30, values.reduce(into: Data()) { $0.append($1) })
    }

    static func set(_ values: [Data]) -> Data {
        tagged(0x31, values.reduce(into: Data()) { $0.append($1) })
    }

    static func integer(_ data: Data) -> Data {
        var value = Data(data.drop(while: { $0 == 0 }))

        if value.isEmpty {
            value = Data([0])
        }

        if value.first.map({ $0 & 0x80 != 0 }) == true {
            value.insert(0, at: 0)
        }

        return tagged(0x02, value)
    }

    static func oid(_ content: [UInt8]) -> Data {
        tagged(0x06, Data(content))
    }

    static func null() -> Data {
        Data([0x05, 0x00])
    }

    static func utf8String(_ value: String) -> Data {
        tagged(0x0C, Data(value.utf8))
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"

        return tagged(
            0x17,
            Data(formatter.string(from: date).utf8)
        )
    }

    static func bitString(_ value: Data) -> Data {
        var content = Data([0x00])
        content.append(value)
        return tagged(0x03, content)
    }

    static func explicit(
        tag: UInt8,
        content: Data
    ) -> Data {
        tagged(0xA0 | tag, content)
    }

    private static func tagged(
        _ tag: UInt8,
        _ content: Data
    ) -> Data {
        var result = Data([tag])
        result.append(length(content.count))
        result.append(content)
        return result
    }

    private static func length(_ value: Int) -> Data {
        if value < 128 {
            return Data([UInt8(value)])
        }

        var number = value
        var bytes: [UInt8] = []

        while number > 0 {
            bytes.insert(UInt8(number & 0xFF), at: 0)
            number >>= 8
        }

        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
