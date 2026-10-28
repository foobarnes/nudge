import SwiftUI

/// Mockup-style segmented control: a soft track with a raised selected segment.
struct Segmented<Option: Hashable>: View {
    struct Segment {
        let option: Option
        let title: String
        var symbol: String? = nil
        var selectedFill: Color? = nil
    }

    let segments: [Segment]
    @Binding var selection: Option
    var trackFill: Color = Tokens.Palette.fill
    var selectedFill: Color = Tokens.Palette.segmentOn
    var text: Color = Tokens.Palette.text
    var selectedText: Color = Tokens.Palette.text
    var height: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments, id: \.option) { segment in
                let on = segment.option == selection
                Button {
                    withAnimation(Motion.pick(.snappy(duration: 0.2), reduced: reduceMotion)) { selection = segment.option }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = segment.symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                        Text(segment.title)
                    }
                    .font(Tokens.Typo.button.weight(on ? .bold : .semibold))
                    .foregroundStyle(on ? selectedText : text)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(segment.selectedFill ?? selectedFill)
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(trackFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
