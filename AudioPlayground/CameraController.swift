//
//  CameraController.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 15/09/26.
//

import Foundation
import SwiftUI
import AVFoundation

final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    
    func start() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.addInput( input )
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.queue"))
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("frame:", CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
