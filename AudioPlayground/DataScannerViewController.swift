//
//  DataScannerViewController.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 12/09/26.
//

import SwiftUI
import VisionKit
import Vision

struct QRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }
    
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }
        
        func dataScanner(_ dataScanner : DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard case let .barcode(barcode) = addedItems.first,
                  let payload = barcode.payloadStringValue else { return }
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
    
    
}
