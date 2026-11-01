import SwiftUI

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CustomRefreshable<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var action: () async -> Void

    @State private var offset: CGFloat = 0
    @State private var refreshing = false
    @State private var rotation: Double = 0
    @State private var scrollOffset: CGFloat = 0

    private let threshold: CGFloat = 70
    private let maxOffset: CGFloat = 100

    var body: some View {
        ScrollView(showsIndicators: false) {
            ZStack(alignment: .top) {
                Color.clear.frame(height: 80)

                VStack(spacing: 6) {
                    if refreshing {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .rotationEffect(.degrees(rotation))
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(rotation))
                            .opacity(min(offset / threshold, 1))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                VStack(spacing: 0) {
                    content()
                }
                .offset(y: max(offset, 0))
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.85), value: offset)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("scroll")).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                scrollOffset = value
            }
        }
        .coordinateSpace(name: "scroll")
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard !refreshing else { return }
                    guard scrollOffset >= 0 else { return }
                    let translation = max(0, value.translation.height)
                    offset = min(translation, maxOffset)
                    rotation = min(Double(offset / threshold) * 180, 180)
                }
                .onEnded { _ in
                    if offset >= threshold {
                        refreshing = true
                        withAnimation(.easeOut(duration: 0.25)) {
                            offset = 50
                        }
                        Task {
                            await action()
                            withAnimation(.easeOut(duration: 0.25)) {
                                refreshing = false
                                offset = 0
                                rotation = 0
                            }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) {
                            offset = 0
                            rotation = 0
                        }
                    }
                }
        )
    }
}
