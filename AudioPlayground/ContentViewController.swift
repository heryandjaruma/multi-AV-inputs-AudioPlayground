//
//  ContentViewController.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Foundation
import AVFoundation

@Observable
class ContentViewController {
    var discoveryService = DiscoveryService()

    var audioCaptureService = AudioCaptureService()

    var audioPlaybackService = AudioPlaybackService()

    init() {
        audioCaptureService.onAudioCaptured = { [weak self] buffer, _ in
            guard let self, let packet = buffer.encodedForTransport() else { return }
            DispatchQueue.main.async {
                self.discoveryService.sendMonitorAudio(packet)
            }
        }

        discoveryService.onAudioReceived = { [weak self] buffer in
            self?.audioPlaybackService.play(buffer)
        }
    }
}
