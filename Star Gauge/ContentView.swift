//
//  ContentView.swift
//  Star Gauge
//
//  Created by Travis Pierce on 12/13/25.
//

import SwiftUI

struct ZoomableFillImageView: View {
    let image: Image
    @Binding var zoomScale: CGFloat
    @Binding var offset: CGSize

    var body: some View {
        GeometryReader { geo in
            image
                .resizable()
                .scaledToFill() // fill the view
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped() // ensure no spill outside
                .offset(x: offset.width, y: offset.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Update offset with drag, then clamp to bounds
                            offset = CGSize(width: offset.width + value.translation.width,
                                            height: offset.height + value.translation.height)

                            // Clamp based on current zoom
                            let imageW = geo.size.width * zoomScale
                            let imageH = geo.size.height * zoomScale
                            let maxX = max(0, (imageW - geo.size.width) / 2)
                            let maxY = max(0, (imageH - geo.size.height) / 2)

                            offset.width = min(max(offset.width, -maxX), maxX)
                            offset.height = min(max(offset.height, -maxY), maxY)
                        }
                        .onEnded { _ in
                            // Optional: snap or fine-tune after release
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            zoomScale = scale
                        }
                )
        }
        .ignoresSafeArea() // optional; keeps the image edge-to-edge
    }
}

struct ContentView: View {
    @State private var zoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    var body: some View {
        ZoomableFillImageView(image: Image("star_gauge_image"),
                              zoomScale: $zoomScale,
                              offset: $offset)
            .ignoresSafeArea()
    }
}

// If you already have ZoomableFillImageView defined above, you can preview ContentView.
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDevice("iPhone 14") // optional: pick a device
    }
}

