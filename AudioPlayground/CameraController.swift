//
//  CameraController.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 15/09/26.
//

import Foundation
import SwiftUI
import AVFoundation
import Photos

final class CameraController: NSObject,
AVCaptureVideoDataOutputSampleBufferDelegate,
                              AVCaptureAudioDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    
    var writer: AVAssetWriter!
    var videoInput: AVAssetWriterInput!
    var audioInput: AVAssetWriterInput!
    var started = false
    
    func start() {
        if session.inputs.isEmpty && session.outputs.isEmpty {
            session.beginConfiguration()

            let sampleQueue = DispatchQueue(label: "sample.queue")

            // video
            if let vDevice = AVCaptureDevice.default(for: .video),
               let vInput = try? AVCaptureDeviceInput(device: vDevice) {
                session.addInput( vInput )
            }
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            session.addOutput(videoOutput)

            // audio
            if let aDevice = AVCaptureDevice.default(for: .audio),
               let aInput = try? AVCaptureDeviceInput(device: aDevice) {
                session.addInput(aInput)
            }
            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            session.addOutput(audioOutput)

            session.commitConfiguration()
        }

        started = false

        // writer setup
        let url = URL.documentsDirectory.appending(path: "out-\(UUID().uuidString).mov")
        writer = try? AVAssetWriter(url: url, fileType: .mov)
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720
        ])
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100
        ])
        audioInput.expectsMediaDataInRealTime = true
        writer.add(audioInput)
        
        let sessionQueue = DispatchQueue(label: "session.queue")
        sessionQueue.async {
            self.session.startRunning()
        }
        
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }
        
        if output is AVCaptureVideoDataOutput, videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput, audioInput.isReadyForMoreMediaData {
            audioInput.append(sampleBuffer)
        }
    }
    
    func stop() {
        session.stopRunning()
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        writer.finishWriting {
            print("writer status:", self.writer.status.rawValue, self.writer.error ?? "no error")
            guard self.writer.status == .completed else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.writer.outputURL)
            } completionHandler: { success, error in
                print("Saved to photos", success, error ?? "")
            }
        }
    }
}
