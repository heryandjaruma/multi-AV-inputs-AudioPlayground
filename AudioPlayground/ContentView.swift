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
                .onAppear {
                    controller.start()
                }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
