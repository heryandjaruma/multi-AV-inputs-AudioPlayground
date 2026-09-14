//
//  ContentViewController.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Foundation
import AVFoundation

@MainActor
@Observable
class ContentViewController {
    var discoveryService = DiscoveryService()

    var audioCaptureService = AudioCaptureService()

    var audioPlaybackService = AudioPlaybackService()

    init() {
        let discoveryService = discoveryService // hoist a local, non-isolated ref
        audioCaptureService.onAudioCaptured = { buffer, _ in
            guard let packet = buffer.encodedForTransport() else { return }
            discoveryService.sendMonitorAudio(packet)
            discoveryService.sendMasterAudio(packet)
        }

        discoveryService.onAudioReceived = { [weak self] buffer in
            Task {
                self?.audioPlaybackService.play(buffer)                
            }
        }
    }
}
