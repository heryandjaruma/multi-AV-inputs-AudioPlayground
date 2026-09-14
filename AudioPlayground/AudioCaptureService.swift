//
//  AudioBufferMonitor.swift
//  AudioCaptureService
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Foundation
import AVFoundation

@Observable
nonisolated final class AudioCaptureService {
    private let engine = AVAudioEngine()
    
    var onAudioCaptured: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    
    func start() {
        let input = engine.inputNode // get the input node
        let format = input.inputFormat(forBus: 0)
        
        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format
        ) { [weak self] buffer, time in
            guard let self else { return }
            self.onAudioCaptured?(buffer, time)
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
    }
}
