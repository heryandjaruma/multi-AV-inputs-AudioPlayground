//
//  AudioPlaybackService.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Foundation
import AVFoundation

@Observable
final class AudioPlaybackService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false
    private var session = AVAudioSession.sharedInstance()

    func start() {
        guard !engine.attachedNodes.contains(player) else { return }
        engine.attach(player)

        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                print("Failed to set audio session category: \(error.localizedDescription)")
            }
        }
    }

    func play(_ buffer: AVAudioPCMBuffer) {
        if !isRunning {
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            do {
                try engine.start()
            } catch {
                print("Playback engine start failed: \(error)")
                return
            }
            player.play()
            isRunning = true
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        player.stop()
        engine.stop()
        if engine.attachedNodes.contains(player) {
            engine.disconnectNodeOutput(player)
        }
        isRunning = false
    }
}
