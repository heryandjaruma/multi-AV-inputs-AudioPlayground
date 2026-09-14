//
//  AudioPCMTransport.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Foundation
import AVFoundation

struct PCMPacketHeader {
    let sampleRate: Double
    let channelCount: UInt32
    let frameCount: UInt32
    static let size = 16

    init(sampleRate: Double, channelCount: UInt32, frameCount: UInt32) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
    }

    init?(_ data: Data) {
        guard data.count >= Self.size else { return nil }
        let bytes = [UInt8](data.prefix(Self.size))
        let sampleRateBits = bytes[0..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        sampleRate = Double(bitPattern: sampleRateBits)
        channelCount = bytes[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        frameCount = bytes[12..<16].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    var encoded: Data {
        var data = Data(capacity: Self.size)
        withUnsafeBytes(of: sampleRate.bitPattern.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: channelCount.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: frameCount.bigEndian) { data.append(contentsOf: $0) }
        return data
    }
}

extension AVAudioPCMBuffer {
    func encodedForTransport() -> Data? {
        guard let channelData = floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)
        let frameCount = Int(frameLength)
        guard frameCount > 0 else { return nil }

        var samples = [Float](repeating: 0, count: frameCount * channelCount)
        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                samples[frame * channelCount + channel] = channelData[channel][frame]
            }
        }

        let header = PCMPacketHeader(
            sampleRate: format.sampleRate,
            channelCount: UInt32(channelCount),
            frameCount: UInt32(frameCount)
        )
        var packet = header.encoded
        samples.withUnsafeBufferPointer { packet.append(Data(buffer: $0)) }
        return packet
    }

    static func decodeTransport(_ data: Data) -> AVAudioPCMBuffer? {
        guard let header = PCMPacketHeader(data), header.frameCount > 0, header.channelCount > 0 else { return nil }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: header.sampleRate, channels: header.channelCount) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: header.frameCount) else { return nil }
        buffer.frameLength = header.frameCount

        let sampleCount = Int(header.frameCount) * Int(header.channelCount)
        let sampleData = data.dropFirst(PCMPacketHeader.size)
        guard sampleData.count >= sampleCount * MemoryLayout<Float>.size else { return nil }

        let samples: [Float] = sampleData.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self).prefix(sampleCount))
        }

        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(header.channelCount)
        for frame in 0..<Int(header.frameCount) {
            for channel in 0..<channelCount {
                channelData[channel][frame] = samples[frame * channelCount + channel]
            }
        }
        return buffer
    }
}
