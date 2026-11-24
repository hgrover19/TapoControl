import SwiftUI

/// A slider drawn over a colour gradient (hue, saturation, white temperature).
/// Reports editing start/end so the caller sends one command when the drag ends.
struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false

    init(value: Binding<Double>, range: ClosedRange<Double>, colors: [Color],
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value
        self.range = range
        self.colors = colors
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                    .frame(height: 10)
                Circle()
                    .fill(.white)
                    .shadow(radius: 1)
                    .frame(width: 16, height: 16)
                    .offset(x: CGFloat(fraction) * (width - 16))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let x = min(max(gesture.location.x - 8, 0), width - 16)
                        value = range.lowerBound + Double(x / max(width - 16, 1)) * span
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 18)
    }
}
