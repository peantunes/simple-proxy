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
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create temp dir for P12 export: \(error)")
            return
        }

        let keyURL = tempDir.appendingPathComponent("key.pem")
        let certURL = tempDir.appendingPathComponent("cert.pem")

        guard let keyData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data? else {
            print("❌ Failed to get private key data for P12")
            return
        }
        let keyPem = makePem(data: keyData, type: "PRIVATE KEY")
        do {
            try keyPem.data(using: .utf8)?.write(to: keyURL)
        } catch {
            print("❌ Failed to write private key for P12: \(error)")
            return
        }

        let certData = SecCertificateCopyData(certificate) as Data
        let certPem = makePem(data: certData, type: "CERTIFICATE")
        do {
            try certPem.data(using: .utf8)?.write(to: certURL)
        } catch {
            print("❌ Failed to write certificate for P12: \(error)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["pkcs12", "-export", "-in", certURL.path, "-inkey", keyURL.path, "-out", fileURL.path, "-passout", "pass:\(p12Password)"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("❌ Failed to run openssl for P12 export: \(error)")
            return
        }
        guard process.terminationStatus == 0 else {
            print("❌ openssl pkcs12 exited with code \(process.terminationStatus)")
            return
        }
        print("✅ Root Certificate created at \(fileURL.path)")
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
    return SecCertificateRequest(subject: subject)
}

private func SecCreateSelfSignedCertificate(request: SecCertificateRequest, privateKey: SecKey) -> SecCertificate? {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    } catch {
        print("❌ Failed to create temp dir for certificate generation: \(error)")
        return nil
    }

    let keyURL = tempDir.appendingPathComponent("key.pem")
    let certURL = tempDir.appendingPathComponent("cert.pem")

    guard let keyData = SecKeyCopyExternalRepresentation(privateKey, nil) as Data? else {
        print("❌ Failed to get private key data")
        return nil
    }
    let keyPem = makePem(data: keyData, type: "PRIVATE KEY")
    do {
        try keyPem.data(using: .utf8)?.write(to: keyURL)
    } catch {
        print("❌ Failed to write private key: \(error)")
        return nil
    }

    let subjString = request.subject
        .flatMap { $0.compactMap { "/\($0.key)=\($0.value)" } }
        .joined()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    process.arguments = ["req", "-new", "-x509", "-key", keyURL.path, "-subj", subjString, "-days", "3650", "-out", certURL.path]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        print("❌ Failed to run openssl: \(error)")
        return nil
    }
    guard process.terminationStatus == 0 else {
        print("❌ openssl exited with code \(process.terminationStatus)")
        return nil
    }

    guard let certData = try? Data(contentsOf: certURL),
          let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
        print("❌ Failed to create certificate from openssl output")
        return nil
    }

    return certificate
}

private class SecCertificateRequest {
    let subject: [[String: Any]]
    init(subject: [[String: Any]]) {
        self.subject = subject
    }
}

private func makePem(data: Data, type: String) -> String {
    let base64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    return """
    -----BEGIN \(type)-----
    \(base64)
    -----END \(type)-----

    """
}
