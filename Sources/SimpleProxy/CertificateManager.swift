//
//  CertificateManager.swift
//  SimpleProxy
//
//  Created by Pedro Antunes on 28/04/2025.
//

import Foundation
import Security

final class CertificateManager {
    static let shared = CertificateManager()

    private let certificateName = "SimpleProxyRoot"
    private let p12Password = "simpleproxy"
    private let p12Filename = "SimpleProxy.p12"

    private init() {}

    func ensureCertificateExists() {
        let fileURL = certificatesDirectory().appendingPathComponent(p12Filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("✅ Found existing Root Certificate at \(fileURL.path)")
        } else {
            print("⚡ No Root Certificate found. Creating a new one...")
            createRootCertificate(at: fileURL)
        }
    }

    private func createRootCertificate(at fileURL: URL) {
        let kSecOIDCommonName = "2.5.4.3"
        // Create attributes for private key
        let privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: false,
        ]

        let parameters: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: privateKeyAttributes
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
            fatalError("❌ Failed to create private key: \(error!.takeRetainedValue() as Error)")
        }

        let subject = [
            [kSecOIDCommonName as String: certificateName]
        ]

        guard let csr = SecGenerateCertificateRequest(privateKey: privateKey, subject: subject) else {
            fatalError("❌ Failed to generate CSR")
        }

        guard let certificate = SecCreateSelfSignedCertificate(request: csr, privateKey: privateKey) else {
            fatalError("❌ Failed to create self-signed certificate")
        }

        exportP12(certificate: certificate, privateKey: privateKey, to: fileURL)
    }

    private func exportP12(certificate: SecCertificate, privateKey: SecKey, to fileURL: URL) {
        let identityDict: [String: Any] = [
            kSecImportExportPassphrase as String: p12Password
        ]

        var identity: SecIdentity?
        SecIdentityCreateWithCertificate(kCFAllocatorDefault, certificate, &identity)

        guard let identityRef = identity else {
            fatalError("❌ Failed to create identity from certificate")
        }

        let items = [identityRef]

        var p12Data: CFData?
        let x = SecItemImportExportFlags.kSecItemPemArmour
        let status = SecItemExport(items as CFArray, SecExternalFormat.kSecFormatPKCS12, SecItemImportExportFlags.kSecItemPemArmour, identityDict as CFDictionary, &p12Data)

        guard status == errSecSuccess, let data = p12Data else {
            fatalError("❌ Failed to export P12: \(status)")
        }
        
        do {
            try (data as Data).write(to: fileURL)
            print("✅ Root Certificate created at \(fileURL.path)")
        } catch {
            print("❌ Failed to write P12 file: \(error)")
        }
    }

    private func certificatesDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = paths[0].appendingPathComponent("SimpleProxy")

        if !FileManager.default.fileExists(atPath: appSupportURL.path) {
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        return appSupportURL
    }
}

// MARK: - Helpers (simulate CSR & Self-Sign)

private func SecGenerateCertificateRequest(privateKey: SecKey, subject: [[String: Any]]) -> SecCertificateRequest? {
    // TODO: In real implementation, generate CSR.
    return nil
}

private func SecCreateSelfSignedCertificate(request: SecCertificateRequest, privateKey: SecKey) -> SecCertificate? {
    // TODO: In real implementation, create self-signed cert.
    return nil
}

private class SecCertificateRequest {}
