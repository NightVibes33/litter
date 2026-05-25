import SwiftUI
import UIKit

private enum CatTransmissionFrames {
    static let names = [
        "cat_transmission_01",
        "cat_transmission_02",
        "cat_transmission_03",
        "cat_transmission_04",
        "cat_transmission_05",
        "cat_transmission_06",
    ]

    static let frameDurationMs: UInt64 = 82
    static let holdDelaySeconds: Double = 0.5
    static let holdMaxDistance: CGFloat = 12
}

struct CatTransmissionPressView<Content: View>: View {
    @State private var transmissionActive = false

    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            if transmissionActive {
                CatTransmissionFramePlayer()
            } else {
                content()
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: CatTransmissionFrames.holdDelaySeconds,
            maximumDistance: CatTransmissionFrames.holdMaxDistance,
            pressing: { isPressing in
                if !isPressing {
                    stopHold()
                }
            },
            perform: {
                transmissionActive = true
            }
        )
        .onDisappear {
            stopHold()
        }
    }

    private func stopHold() {
        transmissionActive = false
    }
}

private struct CatTransmissionFramePlayer: View {
    @State private var frameIndex = 0

    var body: some View {
        ZStack {
            if let image = UIImage(named: CatTransmissionFrames.names[frameIndex]) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            }
        }
        .clipped()
        .task {
            frameIndex = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(CatTransmissionFrames.frameDurationMs))
                frameIndex = (frameIndex + 1) % CatTransmissionFrames.names.count
            }
        }
    }
}
