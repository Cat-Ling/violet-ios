import SwiftUI

struct ReaderSlider: View {
    @Binding var value: Double
    @Binding var isScrolling: Bool
    var range: ClosedRange<Double>
    
    @State private var lastOffset: Double = 0
    @Environment(\.colorScheme) var colorScheme

    var knobSize: CGSize = .init(width: 25, height: 25)
    var barSize: CGFloat = 6.0

    var backgroundBarColor: Color { 
        colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.8) 
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
                    // BG
                    RoundedRectangle(cornerRadius: 50)
                        .frame(height: barSize)
                        .foregroundColor(backgroundBarColor)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(backgroundBarColor, lineWidth: 1.5)
                        }

                    // Trailing (Filled part)
                    RoundedRectangle(cornerRadius: 50)
                        .foregroundColor(Color.accentColor)
                        .frame(
                            width: $value.wrappedValue.map(
                                from: range,
                                to: knobSize.width ... max(geometry.size.width, knobSize.width)
                            ),
                            height: barSize
                        )

                    // KNOB
                    RoundedRectangle(cornerRadius: 50)
                        .frame(width: knobSize.width, height: knobSize.height, alignment: .center)
                        .foregroundColor(.white)
                        .scaleEffect(isScrolling ? 1.25 : 1.0)
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                        .offset(x: $value.wrappedValue.map(from: range, to: 0 ... max(geometry.size.width - knobSize.width, 0)))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { dragValue in
                                    isScrolling = true
                                    
                                    // Use absolute touch location rather than relative translation,
                                    // so the knob instantly snaps to wherever the user taps/drags.
                                    let sliderPos = max(0, min(Double(dragValue.location.x) - Double(knobSize.width / 2), Double(geometry.size.width - knobSize.width)))
                                    let sliderVal = sliderPos.map(from: 0 ... Double(geometry.size.width - knobSize.width), to: range)

                                    self.value = sliderVal
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        isScrolling = false
                                    }
                                }
                        )
                }
            }
        }
        .frame(height: knobSize.height)
    }
}
