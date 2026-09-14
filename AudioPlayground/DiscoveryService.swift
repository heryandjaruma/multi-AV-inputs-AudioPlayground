//
//  DiscoveryService.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 13/09/26.
//

import Network
import CryptoKit
import Crypto
import X509
import SwiftASN1
import Security
import SwiftUI
import CoreImage.CIFilterBuiltins

@Observable
final class DiscoveryService {
    private var listener: NWListener?
    var listenerState: NWListener.State = .setup
    
    private var browser: NWBrowser?
    var browserState: NWBrowser.State = .setup
    
    var discoveredPeers: [NWBrowser.Result] = []
    
    var connectionGroup: NWConnectionGroup?
    var controlStream: NWConnection?
    var audioStream: NWConnection?
    
    var connected: Bool = false
    
    // MARK: - Host / Advertiser
    
    var qrCodeImage: CGImage?
    var hostIdentity: SecIdentity?
    
    func makeServerQUICParameters(identity: SecIdentity) -> NWParameters {
        let quic = NWProtocolQUIC.Options(alpn: ["avcontinuity"])
        guard let secIdentity = sec_identity_create(identity) else { fatalError("Bad identity") }
        sec_protocol_options_set_local_identity(quic.securityProtocolOptions, secIdentity)
        let parameters = NWParameters(quic: quic)
        parameters.includePeerToPeer = true
        return parameters
    }
    
    func startAdvertising(identity: SecIdentity) {
        listener = try? NWListener(using: makeServerQUICParameters(identity: identity))
        listener?.service = NWListener.Service(name: "dev.heryan.multi-AV-inputs.AudioPlayground", type: "_avcontinuity._udp")
        
        listener?.stateUpdateHandler = { [weak self] newState in
            self?.listenerState = newState
        }
        
        listener?.newConnectionGroupHandler = { [weak self] groupConnection in
            self?.handleIncomingGroup(groupConnection)
        }
        
        listener?.start(queue: .main)
    }
    var isListenerActive: Bool {
        if case .ready = listenerState {
            return true
        }
        return false
    }
    func handleIncomingGroup(_ group: NWConnectionGroup) {
        group.stateUpdateHandler = { state in
            switch state {
            case .setup: break
            case .waiting(let error): print("Group waiting: \(error)")
            case .ready: print("Group ready")
            case .failed(let error): print("Group failed: \(error)")
            case .cancelled: print("Group cancelled")
            default: break
            }
        }
        group.newConnectionHandler = { [weak self] stream in
            guard let self else { return }
            stream.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled:
                    self.connected = false
                default: break
                }
            }
            stream.start(queue: .main)
            self.identifyIncomingStream(stream)
        }
        group.start(queue: .main)
    }
    
    func stopBrowsing() {
        browser?.cancel()
    }
    
    func loadOrCreateHostIdentity(label: String = "dev.heryan.avcontinuity.host") throws -> SecIdentity {
        if let existing = try? findIdentity(label: label) { return existing }
        
        let privateKey = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(privateKey)
        let name = try DistinguishedName { CommonName(label) }
        let now = Date()
        let extensions = try Certificate.Extensions {
            Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
            Critical(KeyUsage(digitalSignature: true, keyCertSign: true))
        }
        let certificate = try Certificate(version: .v3, serialNumber: Certificate.SerialNumber(), publicKey: certKey.publicKey, notValidBefore: now, notValidAfter: now.addingTimeInterval(3650 * 24 * 3600), issuer: name, subject: name, signatureAlgorithm: .ecdsaWithSHA256, extensions: extensions, issuerPrivateKey: certKey)
        let secCertificate = try SecCertificate.makeWithCertificate(certificate)
        
        let publicKeyBytes = privateKey.publicKey.x963Representation
        let applicationLabel = Data(Insecure.SHA1.hash(data: publicKeyBytes))
        
        var keyError: Unmanaged<CFError>?
        let keyCreateAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        guard let secKey = SecKeyCreateWithData(privateKey.x963Representation as CFData, keyCreateAttrs as CFDictionary, &keyError) else {
            throw keyError!.takeRetainedValue()
        }
        
        let keyAddStatus = SecItemAdd([
            kSecClass: kSecClassKey,
            kSecValueRef: secKey,
            kSecAttrLabel: label,
            kSecAttrApplicationLabel: applicationLabel,
            kSecUseDataProtectionKeychain: true
        ] as CFDictionary, nil)
        guard keyAddStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(keyAddStatus)) }
        
        let addStatus = SecItemAdd([
            kSecClass: kSecClassCertificate,
            kSecValueRef: secCertificate,
            kSecAttrLabel: label,
            kSecUseDataProtectionKeychain: true
        ] as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
        
        var certAttrsResult: CFTypeRef?
        SecItemCopyMatching([
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: label,
            kSecUseDataProtectionKeychain: true,
            kSecReturnAttributes: true
        ] as CFDictionary, &certAttrsResult)
        let certPubKeyHash = (certAttrsResult as? [String: Any])?[kSecAttrPublicKeyHash as String] as? Data
        
        return try findIdentity(label: label)
    }
    
    private func findIdentity(label: String) throws -> SecIdentity {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: label,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true
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
        let parameters = NWParameters(quic: quic)
        parameters.includePeerToPeer = true
        return parameters
    }

    func startBrowsing(pinnedHash: Data) {
        let browserParameters = NWParameters.udp
        browserParameters.includePeerToPeer = true
        browser = NWBrowser(for: .bonjour(type: "_avcontinuity._udp", domain: nil), using: browserParameters)
        browser?.stateUpdateHandler = { [weak self] newState in
            self?.browserState = newState
        }
        browser?.browseResultsChangedHandler = { results, _ in
            guard let result = results.first else { return }
            let groupConnection = NWConnectionGroup(with: NWMultiplexGroup(to: result.endpoint), using: self.makeClientQUICParameters(pinnedHash: pinnedHash))
            self.startConnectionGroup(groupConnection)
        }
        browser?.start(queue: .main)
    }
    var isBrowserActive: Bool {
        if case .ready = browserState {
            return true
        }
        return false
    }
    
    func startConnectionGroup(_ group: NWConnectionGroup) {
        group.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connected = true
                let control = NWConnection(from: group)
                let audio = NWConnection(from: group)
                control?.stateUpdateHandler = { [weak self] state in
                    guard let self, case .ready = state else { return }
                    self.connected = true
                    self.sendTag(Self.controlTag, on: control!)
                }
                audio?.stateUpdateHandler = { [weak self] state in
                    guard let self, case .ready = state else { return }
                    self.sendTag(Self.audioTag, on: audio!)
                }
                control?.start(queue: .main)
                audio?.start(queue: .main)
                if let control { self.receive(control) }
                if let audio { self.receive(audio) }
                self.controlStream = control
                self.audioStream = audio
            case .failed(let error):
                print("Group failed: \(error)")
                self.connected = false
            case .cancelled:
                self.connected = false
            default: break
            }
        }
        group.newConnectionHandler = { stream in
            print("Unexpected incoming stream from host (id: \(ObjectIdentifier(stream)))")
        }
        group.start(queue: .main)
        self.connectionGroup = group
    }
    
    func stopAdvertising() {
        listener?.cancel()
    }
    
    // MARK: - Shared

    private static let controlTag = "control"
    private static let audioTag = "audio"

    private func sendTag(_ tag: String, on connection: NWConnection) {
        connection.send(content: tag.data(using: .utf8), completion: .contentProcessed({ error in
            if let error {
                print("Tag send error: \(error)")
            }
        }))
    }

    private func identifyIncomingStream(_ stream: NWConnection) {
        stream.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, _, error in
            guard let self else { return }
            if let error {
                print("Stream identify error: \(error)")
                return
            }
            guard let content, let tag = String(data: content, encoding: .utf8) else {
                return
            }
            switch tag {
            case Self.controlTag:
                self.controlStream = stream
            case Self.audioTag:
                self.audioStream = stream
            default:
                print("Unknown stream tag: \(tag)")
                return
            }
            self.connected = true
            self.receive(stream)
        }
    }

    func receive(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, contentContext, isComplete, error in
            if let content, let msg = String(data: content, encoding: .utf8) {
                print("Received: \(msg)")
            }
            if let error {
                print("Receive error: \(error)")
                return
            }
            self.receive(connection)
        }
    }
    
    func sendPing() {
        let data = "ping".data(using: .utf8)
        controlStream?.send(content: data, completion: .contentProcessed({ error in
            if let error {
                print("Send error: \(error)")
            }
        }))
    }
    
}
