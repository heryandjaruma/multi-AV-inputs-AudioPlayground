//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins


import VisionKit
import Network

struct ContentView: View {
    @State private var discoveryController = ContentViewController()
    
    @State
    private var isRunning = false
    
    @State
    var isShowingScanner = false
    var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Listener
            if let cgImage = discoveryController.discoveryService.qrCodeImage, discoveryController.discoveryService.isListenerActive, !discoveryController.discoveryService.connected {
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
            }
            
            Button("\(discoveryController.discoveryService.isListenerActive ? "Stop" : "Start") Listener") {
                guard let identity = discoveryController.discoveryService.hostIdentity else { return }
                discoveryController.discoveryService.isListenerActive
                ? discoveryController.discoveryService.stopAdvertising()
                : discoveryController.discoveryService.startAdvertising(identity: identity)
            }
            .disabled(discoveryController.discoveryService.hostIdentity == nil)
            
            if discoveryController.discoveryService.isListenerActive, discoveryController.discoveryService.connected {
                HostMonitorView(discoveryService: discoveryController.discoveryService)
            }
            
            // Browser
            Button("\(discoveryController.discoveryService.isBrowserActive ? "Stop" : "Start") Browser") {
                if discoveryController.discoveryService.isBrowserActive {
                    discoveryController.discoveryService.stopBrowsing()
                } else if scannerAvailable {
                    isShowingScanner = true
                }
            }
            .disabled(!scannerAvailable && !discoveryController.discoveryService.isBrowserActive)
            .sheet(isPresented: $isShowingScanner) {
                QRScannerView { payload in
                    isShowingScanner = false
                    guard let pinnedHash = Data(base64Encoded: payload) else { return }
                    discoveryController.discoveryService.startBrowsing(pinnedHash: pinnedHash)
                }
            }
            if discoveryController.discoveryService.isBrowserActive, discoveryController.discoveryService.connected {
                ClientMonitorView(discoveryService: discoveryController.discoveryService)
            }
            List(discoveryController.discoveryService.discoveredPeers, id: \.endpoint) { result in
                Text("\(result.endpoint)")
            }
        }
        .onAppear {
            discoveryController.discoveryService.setupHost()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}


// MARK: - Monitor View

struct ClientMonitorView: View {
    var discoveryService: DiscoveryService
    var body: some View {
        Text("Ready to transmit audio")
        Button("Send Browser Ping") {
            discoveryService.sendPing()
        }
    }
}

struct HostMonitorView: View {
    var discoveryService: DiscoveryService
    var body: some View {
        Text("Ready to receive audio")
        Button("Send Advertiser Ping") {
            discoveryService.sendPing()
        }
    }
}
