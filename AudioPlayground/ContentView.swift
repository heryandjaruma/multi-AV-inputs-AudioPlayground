//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import AVFoundation

@Observable
@MainActor
final class AudioBufferMonitor {
    var lastFrameCount: AVAudioFrameCount = 0
    var pushCount: Int = 0
    var history: [AVAudioPCMBuffer] = []
    
    private let engine = AVAudioEngine()
    
    func start() {
        let input = engine.inputNode // get the input node
        let format = input.inputFormat(forBus: 0)
        
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            
            let lastFrameCount = buffer.frameLength
            
            Task { @MainActor in
                self.lastFrameCount = lastFrameCount
                self.pushCount += 1
                self.history.append(buffer)
                if self.history.count > 20 {
                    self.history.removeFirst()
                }
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("Engine start failed: \(error)")
        }
    }
    
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pushCount = 0
        history.removeAll()
    }
    
}

struct ContentView: View {
    @State private var monitor = AudioBufferMonitor()
    @State private var isRunning = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Last buffer: \(monitor.lastFrameCount) frames")
            Text("Pushes: \(monitor.pushCount)")
            Button(isRunning ? "Stop" : "Start") {
                isRunning.toggle()
                isRunning ? monitor.start() : monitor.stop()
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
