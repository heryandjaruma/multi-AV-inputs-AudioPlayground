//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import Network

@Observable
final class DiscoveryService {
    private var listener: NWListener?
    var listenerState: NWListener.State = .setup
    
    private var browser: NWBrowser?
    var browserState: NWBrowser.State = .setup
    
    var discoveredPeers: [NWBrowser.Result] = []
    
    var connection: NWConnection?
    
    func startAdvertising() {
        listener = try? NWListener(using: .udp)
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
    
    func startBrowsing() {
        browser = NWBrowser(for: .bonjour(type: "_avcontinuity._udp", domain: nil), using: .udp)
        browser?.stateUpdateHandler = { [weak self] newState in
            self?.browserState = newState
        }
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let result = results.first else { return }
            let connection = NWConnection(to: result.endpoint, using: .udp)
            self?.startConnection(connection)
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
    
    func stopBrowsing() {
        
        browser?.cancel()
    }
    
    func stopAdvertising() {
        
        listener?.cancel()
    }
}

struct ContentView: View {
    @State private var discoveryService = DiscoveryService()
    @State private var isRunning = false
    
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
