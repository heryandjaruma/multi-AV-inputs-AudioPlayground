//
//  Protocols.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Network
import Foundation

enum ControlMessageType: UInt32 {
    case ping = 1
    case pong = 2
    case acceptConnection = 3
}

extension NWProtocolFramer.Message {
    convenience init(type: ControlMessageType) {
        self.init(definition: ControlProtocolFramer.definition)
        self["type"] = type
    }
    var type: ControlMessageType {
        get { self["type"] as? ControlMessageType ?? .ping}
        set { self["type"] = newValue}
    }
}

struct ControlHeader {
    let type: UInt32
    let length: UInt32
    static let size = 8
    
    init(type: UInt32, length: UInt32) {
        self.type = type
        self.length = length
    }
    init(_ buffer: UnsafeMutableRawBufferPointer) {
        var t: UInt32 = 0, l: UInt32 = 0
        withUnsafeMutableBytes(of: &t) {
            $0.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!, count: 4))
        }
        withUnsafeMutableBytes(of: &l) {
            $0.copyMemory(from: UnsafeRawBufferPointer(start: buffer.baseAddress!.advanced(by: 4), count: 4))
        }
        type = t; length = l
    }
    var encoded: Data {
        var t = type, l = length
        return Data(bytes: &t, count: 4) + Data(bytes: &l, count: 4)
    }
}

final class ControlProtocolFramer: NWProtocolFramerImplementation {
    static let label = "Control"
    static let definition = NWProtocolFramer.Definition(implementation: ControlProtocolFramer.self)
    
    init(framer: NWProtocolFramer.Instance) {
        
    }
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        .ready
    }
    func wakeup(framer: NWProtocolFramer.Instance) {
        
    }
    func stop(framer: NWProtocolFramer.Instance) -> Bool {
        true
    }
    func cleanup(framer: NWProtocolFramer.Instance) {
        
    }
    
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var header: ControlHeader?
            let parsed = framer.parseInput(minimumIncompleteLength: ControlHeader.size, maximumLength: ControlHeader.size) { buffer, isComplete in
                guard let buffer, buffer.count >= ControlHeader.size else { return 0 }
                header = ControlHeader(buffer)
                return ControlHeader.size
            }
            guard parsed, let header else { return ControlHeader.size }
            
            let type = ControlMessageType(rawValue: header.type) ?? .ping
            let message = NWProtocolFramer.Message(type: type)
            if !framer.deliverInputNoCopy(length: Int(header.length), message: message, isComplete: true) {
                return 0
            }
        }
    }
    
    func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
        let header = ControlHeader(type: message.type.rawValue, length: UInt32(messageLength))
        framer.writeOutput(data: header.encoded)
        try? framer.writeOutputNoCopy(length: messageLength)
    }
}
