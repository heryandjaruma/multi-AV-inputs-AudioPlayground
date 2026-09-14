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
import AVFoundation
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
    var monitorStream: NWConnection?
    var masterStream: NWConnection?
    
    var connected: Bool = false

    var onAudioReceived: ((AVAudioPCMBuffer) -> Void)?

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
                let monitor = NWConnection(from: group)
                let master = NWConnection(from: group)

                control?.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.connected = true
                        self.sendFramed(Data("ping".utf8), kind: .control, on: control!)
                    case .failed, .cancelled:
                        self.connected = false
                    default: break
                    }
                }
                self.trackFailures(monitor)
                self.trackFailures(master)

                control?.start(queue: .main)
                monitor?.start(queue: .main)
                master?.start(queue: .main)
                if let control { self.receive(control) }
                if let monitor { self.receive(monitor) }
                if let master { self.receive(master) }

                self.controlStream = control
                self.monitorStream = monitor
                self.masterStream = master
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

    private func trackFailures(_ connection: NWConnection?) {
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connected = false
            default: break
            }
        }
    }

    private func sendFramed(_ data: Data, kind: AVKind, on connection: NWConnection, completion: (() -> Void)? = nil) {
        let header = AVHeader(kind: kind, length: UInt32(data.count))
        connection.send(content: header.encoded + data, completion: .contentProcessed({ error in
            if let error {
                print("Send error (\(kind)): \(error)")
            }
            completion?()
        }))
    }

    private func receiveOnce(_ connection: NWConnection, completion: @escaping (AVKind, Data) -> Void) {
        connection.receive(minimumIncompleteLength: AVHeader.size, maximumLength: AVHeader.size) { content, _, _, error in
            if let error {
                print("Receive error: \(error)")
                return
            }
            guard let content, let header = AVHeader(content) else { return }
            guard header.length > 0 else {
                completion(header.kind, Data())
                return
            }
            connection.receive(minimumIncompleteLength: Int(header.length), maximumLength: Int(header.length)) { payload, _, _, error in
                if let error {
                    print("Receive error: \(error)")
                    return
                }
                completion(header.kind, payload ?? Data())
            }
        }
    }

    private func identifyIncomingStream(_ stream: NWConnection) {
        receiveOnce(stream) { [weak self] kind, data in
            guard let self else { return }
            switch kind {
            case .control: self.controlStream = stream
            case .monitor: self.monitorStream = stream
            case .master: self.masterStream = stream
            }
            self.connected = true
            self.handleReceived(kind: kind, data: data)
            self.receive(stream)
        }
    }

    func receive(_ connection: NWConnection) {
        receiveOnce(connection) { [weak self] kind, data in
            guard let self else { return }
            self.handleReceived(kind: kind, data: data)
            self.receive(connection)
        }
    }

    private func handleReceived(kind: AVKind, data: Data) {
        if kind == .monitor {
            guard let buffer = AVAudioPCMBuffer.decodeTransport(data) else { return }
            onAudioReceived?(buffer)
            return
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            print("Received [\(kind)]: \(text)")
        }
    }

    func sendPing() {
        guard let controlStream else { return }
        sendFramed(Data("ping".utf8), kind: .control, on: controlStream)
    }
    
    // MARK: - SENDING
    private var stateQueue = DispatchQueue(label: "discovery.audio.state")

    // MARK: - Monitor Audio
    private var isSendingMonitor = false
    func sendMonitorAudio(_ data: Data) {
        stateQueue.async { [weak self] in
            guard let self, let monitorStream, !self.isSendingMonitor else { return }
            self.isSendingMonitor = true
            self.sendFramed(data, kind: .monitor, on: monitorStream) {
                self.stateQueue.async {
                    self.isSendingMonitor = false
                }
            }
        }
    }
    
    
    // MARK: - Master Audio
    private var masterQueue: [Data] = []
    private var isSendingMaster = false
    func sendMasterAudio(_ data: Data) {
        stateQueue.async { [weak self] in
            self?.masterQueue.append(data)
            self?.drainMaster()
        }
    }
    func drainMaster() {
        guard let masterStream, !isSendingMaster, let next = masterQueue.first else { return }
        isSendingMaster = true
        masterQueue.removeFirst()
        sendFramed(next, kind: .master, on: masterStream) { [weak self] in
            self?.stateQueue.async {
                self?.isSendingMaster = false
                self?.drainMaster()
            }
        }
    }

}
