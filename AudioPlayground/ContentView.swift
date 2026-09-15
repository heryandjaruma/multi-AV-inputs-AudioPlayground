//
//  ContentView.swift
//  AudioPlayground
//
//  Created by Heryan Djaruma on 10/09/26.
//

import SwiftUI

struct ContentView: View {
    let controller = CameraController()
    var body: some View {
        VStack {
            Color.black
            Button("Start Recording") {
                controller.start()
            }
            .disabled(controller.started)
            
            Button("Stop and Save") {
                controller.stop()
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
