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
    @State
    private var discoveryService = DiscoveryService()
    @State
    private var isRunning = false
    
    @State
    var isShowingScanner = false
    var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if let cgImage = discoveryService.qrCodeImage, discoveryService.isListenerActive {
                Image(decorative: cgImage, scale: 1)
                    .interpolation(.none)   // keep QR modules crisp, don't blur-smooth them
                    .resizable()
                    .frame(width: 200, height: 200)
            }
            Button("\(discoveryService.isListenerActive ? "Stop" : "Start") Listener") {
                guard let identity = discoveryService.hostIdentity else { return }
                discoveryService.isListenerActive
                ? discoveryService.stopAdvertising()
                : discoveryService.startAdvertising(identity: identity)
            }
            .disabled(discoveryService.hostIdentity == nil)
            if discoveryService.isListenerActive, discoveryService.connected {
                Button("Send Browser Ping") {
                    discoveryService.sendPing()
                }
            }
            Button("\(discoveryService.isBrowserActive ? "Stop" : "Start") Browser") {
                if discoveryService.isBrowserActive {
                    discoveryService.stopBrowsing()
                } else if scannerAvailable {
                    isShowingScanner = true
                }
            }
            .disabled(!scannerAvailable && !discoveryService.isBrowserActive)
            .sheet(isPresented: $isShowingScanner) {
                QRScannerView { payload in
                    isShowingScanner = false
                    guard let pinnedHash = Data(base64Encoded: payload) else { return }
                    discoveryService.startBrowsing(pinnedHash: pinnedHash)
                }
            }
            if discoveryService.isBrowserActive, discoveryService.connected {
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
