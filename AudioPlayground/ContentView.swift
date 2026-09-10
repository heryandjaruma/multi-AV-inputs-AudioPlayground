//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI
import AVFAudio

struct ContentView: View {
    
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var isRecording = false
    
    private let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("clip.m4a")
    
    var body: some View {
        VStack {
            Button(isRecording ? "Stop" : "Record") {
                isRecording ? stop() : record()
            }
            Button("Play") {
                player = try? AVAudioPlayer(contentsOf: fileUrl)
                player?.play()
            }
        }
        .onAppear {
            AVAudioApplication.requestRecordPermission { granted in
                print("Mic permission granted: \(granted)")
                
            }
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        .padding()
    }
    
    private func record() {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1
        ]
        do {
            recorder = try AVAudioRecorder(url: fileUrl, settings: settings)
            recorder?.record()
            isRecording = true
        } catch {
            print("Record failed: \(error)")
        }
        
    }
    
    private func stop() {
        recorder?.stop()
        isRecording = false
    }
}

#Preview {
    ContentView()
}
