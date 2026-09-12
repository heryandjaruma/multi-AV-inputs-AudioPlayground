//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

import Network
import CryptoKit
import Crypto
import X509
import SwiftASN1
import Security

@Observable
final class DiscoveryService {
    private var listener: NWListener?
    var listenerState: NWListener.State = .setup
    
    private var browser: NWBrowser?
    var browserState: NWBrowser.State = .setup
    
    var discoveredPeers: [NWBrowser.Result] = []
    
    var connection: NWConnection?
    
    // MARK: - Host / Advertiser
    
    private var qrCodeImage: CGImage?
    var hostIdentity: SecIdentity?
    
    func makeServerQUICParameters(identity: SecIdentity) -> NWParameters {
        let quic = NWProtocolQUIC.Options(alpn: ["avcontinuity"])
        guard let secIdentity = sec_identity_create(identity) else { fatalError("Bad identity") }
        sec_protocol_options_set_local_identity(quic.securityProtocolOptions, secIdentity)
        return NWParameters(quic: quic)
    }
    
    func startAdvertising(identity: SecIdentity) {
        listener = try? NWListener(using: makeServerQUICParameters(identity: identity))
        listener?.service = NWListener.Service(name: "dev.heryan.multi-AV-inputs.AudioPlayground", type: "_avcontinuity._udp")
        
        listener?.stateUpdateHandler = { [weak self] newState in
            self?.listenerState = newState
        }
        
        listener?.newConnectionHandler = { connection in
            self.startConnection(connection)
        }
        
        listener?.start(queue: .main)
    }
    var isListenerActive: Bool {
        if case .ready = listenerState {
            return true
        }
        return false
    }
    
    func stopBrowsing() {
        browser?.cancel()
    }
    
    func loadOrCreateHostIdentity(label: String = "dev.heryan.avcontinuity.host") throws -> SecIdentity {
        if let existing = try? findIdentity(label: label) { return existing } // // stable across launches
        
        let privateKey = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName { CommonName(label) }
        let now = Date()
        
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil)) // irrelevant here — we never run system trust evaluation, only our pinning check
            Critical(KeyUsage(digitalSignature: true, keyCertSign: true))
        }
        
        let certificate = try Certificate(version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: certKey.publicKey, notValidBefore: now, notValidAfter: now.addingTimeInterval(3650 * 24 * 3600), issuer: name, subject: name, signatureAlgorithm: .ecdsaWithSHA256, extensions: extensions, issuerPrivateKey: certKey)
        
        let secCertificate = try SecCertificate.makeWithCertificate(certificate)
        
        var keyError: Unmanaged<CFError>?
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrIsPermanent as String: true,
            kSecAttrLabel as String: label
        ]
        guard SecKeyCreateWithData(privateKey.x963Representation as CFData, keyAttrs as CFDictionary, &keyError) != nil else {
            throw keyError!.takeRetainedValue()
        }
        
        let addStatus = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: secCertificate, kSecAttrLabel: label] as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        
        return try findIdentity(label: label)
    }
    
    private func findIdentity(label: String) throws -> SecIdentity {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassIdentity,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let identity = result else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return identity as! SecIdentity
    }
    
    func fingerprint(of identity: SecIdentity) throws -> String {
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certRef)
        guard let cert = certRef,
              let key = SecCertificateCopyKey(cert),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw NSError(domain: "fingerprint", code: -1)
        }
        return Data(SHA256.hash(data: keyData)).base64EncodedString()
    }
    
    func qrCodeImage(for string: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
    
    func setupHost() {
        do {
            let identity = try loadOrCreateHostIdentity()
            hostIdentity = identity
            qrCodeImage = qrCodeImage(for: try fingerprint(of: identity))
        } catch {
            print("Host identity setup failed: \(error)")
        }
    }
    
    // MARK: - Peer / Client / Listener
    
    func makeClientQUICParameters(pinnedHash: Data) -> NWParameters {
        let quic = NWProtocolQUIC.Options(alpn: ["avcontinuity"])
        sec_protocol_options_set_verify_block(quic.securityProtocolOptions, { _, secTrust, complete in
            let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leaf = chain.first,
                  let key = SecCertificateCopyKey(leaf),
                  let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
                complete(false); return
            }
            complete(Data(SHA256.hash(data: keyData)) == pinnedHash)
        }, .main)
        return NWParameters(quic: quic)
    }
    
    func startBrowsing(pinnedHash: Data) {
        browser = NWBrowser(for: .bonjour(type: "_avcontinuity._udp", domain: nil), using: .udp)
        browser?.stateUpdateHandler = { [weak self] newState in
            self?.browserState = newState
        }
        browser?.browseResultsChangedHandler = { results, _ in
            guard let result = results.first else { return }
            let connection = NWConnection(to: result.endpoint, using: self.makeClientQUICParameters(pinnedHash: pinnedHash))
            self.startConnection(connection)
        }
        browser?.start(queue: .main)
    }
    var isBrowserActive: Bool {
        if case .ready = browserState {
            return true
        }
        return false
    }
    
    func startConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Connected")
                self.sendPing()
            case .failed(let error):
                print("Error: \(error)")
            default: break
            }
        }
        connection.start(queue: .main)
        self.connection = connection
        receive(connection)
    }
    
    func stopAdvertising() {
        listener?.cancel()
    }
    
    // MARK: - Shared
    
    func receive(_ connection: NWConnection) {
        connection.receiveMessage { content, contentContext, isComplete, error in
            if let content, let msg = String(data: content, encoding: .utf8) {
                print("Received: \(msg)")
            }
            if error == nil {
                self.receive(connection)
            }
        }
    }
    
    func sendPing() {
        let data = "ping".data(using: .utf8)
        self.connection?.send(content: data, completion: .contentProcessed({ error in
            if let error {
                print("Send error: \(error)")
            }
        }))
    }
    
}

struct ContentView: View {
    @State
    private var discoveryService = DiscoveryService()
    @State
    private var isRunning = false
    
    var body: some View {
        VStack(spacing: 16) {
            Button("\(discoveryService.isListenerActive ? "Stop" : "Start") Listener") {
                guard let identity = discoveryService.hostIdentity else { return }
                discoveryService.isListenerActive
                ? discoveryService.stopBrowsing()
                : discoveryService.startAdvertising(identity: identity)
            }
            .disabled(discoveryService.hostIdentity == nil)
            if discoveryService.isListenerActive {
                Button("Send Browser Ping") {
                    discoveryService.sendPing()
                }
            }
            Button("\(discoveryService.isBrowserActive ? "Stop" : "Start") Browser") {
                discoveryService.isBrowserActive
                ? discoveryService.stopBrowsing()
                : discoveryService.startBrowsing()
            }
            if discoveryService.isBrowserActive {
                Button("Send Advertiser Ping") {
                    discoveryService.sendPing()
                }
            }
            List(discoveryService.discoveredPeers, id: \.endpoint) { result in
                Text("\(result.endpoint)")
            }
        }
        .onAppear {
            discoveryService.setupHost()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
