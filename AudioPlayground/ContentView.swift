//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import AVFoundation
import AVFAudio

@Observable
@MainActor
final class AudioBufferRecorder {
    var lastFrameCount: AVAudioFrameCount = 0
    var pushCount: Int = 0
    var history: [AVAudioPCMBuffer] = []
    
    private let engine = AVAudioEngine()
    private let file = FileManager.default.temporaryDirectory.appending(path: "rec.caf")
    
    func record() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let file = try? AVAudioFile(
            forWriting: FileManager.default.temporaryDirectory.appending(path: "rec.caf"),
            settings: format.settings
        )
        
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { avAudioPCMBuffer, time in
            try? file?.write(from: avAudioPCMBuffer)
        }
        
        do {
            try engine.start()
        } catch {
            print("Error in starting engine: \(error)")
        }
    }
    
    func stop() {
        engine.inputNode.removeTap(onBus: 0 )
        engine.stop()
    }
    
    func play() {
        let player = AVAudioPlayerNode()
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        
        guard let readFile = try? AVAudioFile(forReading: file) else { return }
        player.scheduleFile(readFile, at: nil)
        try? engine.start()
        player.play()
    }
    
    func setup() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)
    }
}

struct ContentView: View {
    @State private var recorder = AudioBufferRecorder()
    @State private var isRunning = false
    
    var body: some View {
        VStack(spacing: 16) {
            Button(isRunning ? "Stop" : "Record") {
                isRunning.toggle()
                isRunning ? recorder.record() : recorder.stop()
            }
            Button("Play") {
                recorder.play()
            }
        }
        .onAppear {
            recorder.setup()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
