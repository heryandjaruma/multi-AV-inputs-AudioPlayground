//
//  Protocols.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 14/09/26.
//

import Foundation

enum AVKind: UInt8 {
    case control = 1, monitor = 2, master = 3
}

struct AVHeader {
    let kind: AVKind
    let length: UInt32
    static let size = 5

    init(kind: AVKind, length: UInt32) {
        self.kind = kind
        self.length = length
    }
    init?(_ data: Data) {
        guard data.count >= Self.size, let k = AVKind(rawValue: data[data.startIndex]) else { return nil }
        kind = k
        length = data.dropFirst().prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }
    var encoded: Data {
        var l = length.bigEndian
        return Data([kind.rawValue]) + Data(bytes: &l, count: 4)
    }
}
