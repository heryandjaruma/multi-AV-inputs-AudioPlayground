//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import Network
import Security
import CryptoKit

@Observable
final class DiscoveryService {
    private var listener: NWListener?
    var listenerState: NWListener.State = .setup
    
    private var browser: NWBrowser?
    var browserState: NWBrowser.State = .setup
    
    var discoveredPeers: [NWBrowser.Result] = []
    
    var connection: NWConnection?
    
    // MARK: - Host
    
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
    
    // MARK: - Peer
    
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
                if discoveryService.isListenerActive {
                    discoveryService.stopAdvertising()
                } else {
                    discoveryService.startAdvertising()
                }
            }
            if discoveryService.isListenerActive {
                Button("Send Browser Ping") {
                    discoveryService.sendPing()
                }
            }
            Button("\(discoveryService.isBrowserActive ? "Stop" : "Start") Browser") {
                if discoveryService.isBrowserActive {
                    discoveryService.stopBrowsing()
                } else {
                    discoveryService.startBrowsing()
                }
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
        .padding()
    }
}

#Preview {
    ContentView()
}
