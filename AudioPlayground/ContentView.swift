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
    
    func startAdvertising() {
        listener = try? NWListener(using: .udp)
        listener?.service = NWListener.Service(name: "dev.heryan.multi-AV-inputs.AudioPlayground", type: "_avcontinuity._udp")
        
        listener?.stateUpdateHandler = { [weak self] newState in
            self?.listenerState = newState
        }
        
        listener?.newConnectionHandler = { connection in
            connection.start(queue: .main)
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
            self?.discoveredPeers = Array(results)
        }
        browser?.start(queue: .main)
    }
    var isBrowserActive: Bool {
        if case .ready = browserState {
            return true
        }
        return false
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
            Button("\(discoveryService.isBrowserActive ? "Stop" : "Start") Browser") {
                if discoveryService.isBrowserActive {
                    discoveryService.stopBrowsing()
                } else {
                    discoveryService.startBrowsing()
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
