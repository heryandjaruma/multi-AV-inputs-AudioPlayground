//
//  Protocols.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Network
import Foundation

enum AVKind: UInt8 {
    case control = 1, monitor = 2, master = 3
}

extension NWProtocolFramer.Message {
    convenience init(_ kind: AVKind) {
        self.init(definition: AVLinkFramer.definition)
        self["kind"] = kind
    }
    var kind: AVKind { self["kind"] as? AVKind ?? .control }
}

struct AVHeader {
    let kind: AVKind
    let length: UInt32
    static let size = 5

    init(kind: AVKind, length: UInt32) {
        self.kind = kind
        self.length = length
    }
    init?(_ buffer: UnsafeMutableRawBufferPointer) {
        guard buffer.count >= Self.size, let k = AVKind(rawValue: buffer[0]) else { return nil }
        kind = k
        length = UInt32(bigEndian: buffer.loadUnaligned(fromByteOffset: 1, as: UInt32.self))
    }
    var encoded: Data {
        var l = length.bigEndian
        return Data([kind.rawValue]) + Data(bytes: &l, count: 4)
    }
}

final class AVLinkFramer: NWProtocolFramerImplementation {
    static let definition = NWProtocolFramer.Definition(implementation: AVLinkFramer.self)
    static let label = "AVLink"

    init(framer: NWProtocolFramer.Instance) {}
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var header: AVHeader?
            let parsed = framer.parseInput(minimumIncompleteLength: AVHeader.size,
                                           maximumLength: AVHeader.size) { buffer, _ in
                guard let buffer, let h = AVHeader(buffer) else { return 0 }
                header = h
                return AVHeader.size
            }
            guard parsed, let header else { return AVHeader.size }

            let message = NWProtocolFramer.Message(header.kind)
            if !framer.deliverInputNoCopy(length: Int(header.length), message: message, isComplete: true) {
                return 0
            }
        }
    }

    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message,
                      messageLength: Int, isComplete: Bool) {
        let header = AVHeader(kind: message.kind, length: UInt32(messageLength))
        framer.writeOutput(data: header.encoded)
        try? framer.writeOutputNoCopy(length: messageLength)
    }
}
