import SwiftUI

extension PocketFeature {
    var tint: Color {
        switch id { case "notes": return .orange; default: return .teal }
    }
}
struct PocketMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 17)
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.48, blue: 0.51), Color(red: 0.07, green: 0.27, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text("P.").font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(.white))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.white.opacity(0.20), lineWidth: 1))
            .frame(width: 64, height: 64)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}
struct FeatureGlyph: View {
    let feature: PocketFeature
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28).fill(LinearGradient(colors: [feature.tint.opacity(0.90), feature.tint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: feature.symbol).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(.white)
        }.frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: feature.tint.opacity(0.15), radius: 6, y: 3).accessibilityHidden(true)
    }
}
struct PocketSurface: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [.teal.opacity(0.10), .indigo.opacity(0.035), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }
}
struct ToolIllustration: View {
    let feature: PocketFeature
    var body: some View {
        ZStack {
            Circle().fill(feature.tint.opacity(0.16)).frame(width: 140, height: 140)
            Circle().fill(RadialGradient(colors: [feature.tint.opacity(0.22), .clear], center: .center, startRadius: 35, endRadius: 100)).frame(width: 195, height: 195)
            if feature.id == "clipboard" {
                paper.rotationEffect(.degrees(-13)).offset(x: -13, y: -4).opacity(0.5)
                paper.rotationEffect(.degrees(9)).offset(x: 12, y: 1).opacity(0.7)
                paper.overlay(VStack(alignment: .leading, spacing: 9) {
                    HStack { Image(systemName: "text.alignleft"); Spacer(); Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    Capsule().fill(.white.opacity(0.65)).frame(height: 5)
                    Capsule().fill(.white.opacity(0.35)).frame(width: 42, height: 5)
                    RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.15)).frame(height: 28).overlay(Image(systemName: "photo").font(.system(size: 16)))
                }.font(.system(size: 14)).foregroundStyle(.white).padding(14))
            } else {
                paper.rotationEffect(.degrees(-12)).opacity(0.4).offset(x: -10, y: -3)
                paper.overlay(VStack(alignment: .leading, spacing: 11) {
                    Text("A little idea").font(.system(size: 12, weight: .semibold, design: .rounded))
                    HStack { Image(systemName: "checkmark.circle.fill"); Capsule().frame(height: 4) }
                    HStack { Image(systemName: "circle"); Capsule().frame(height: 4).opacity(0.5) }
                    HStack { Image(systemName: "circle"); Capsule().frame(width: 25, height: 4).opacity(0.3) }
                }.foregroundStyle(.white).font(.system(size: 12)).padding(12)).rotationEffect(.degrees(7))
                Text("🦩").font(.system(size: 45)).rotationEffect(.degrees(-10)).offset(x: 49, y: 42)
            }
        }.frame(height: 175).frame(maxWidth: .infinity).accessibilityHidden(true)
    }
    var paper: some View {
        RoundedRectangle(cornerRadius: 13).fill(feature.tint.gradient).frame(width: 94, height: 115)
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
    }
}
struct ToolCard: View {
    let feature: PocketFeature
    var detail: String
    var hint: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ToolIllustration(feature: feature)
                Text(feature.name).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.leading).frame(height: 52, alignment: .top)
                HStack {
                    Text(hint).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(feature.tint)
                        .frame(width: 30, height: 30).background(feature.tint.opacity(0.12)).clipShape(Circle())
                }
            }.padding(18).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(LinearGradient(colors: [feature.tint.opacity(hover ? 0.5 : 0.23), Color.primary.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: feature.tint.opacity(hover ? 0.15 : 0.04), radius: 14, y: 6)
            .offset(y: hover ? -3 : 0)
            .onHover { hover = $0 }.animation(.easeOut(duration: 0.16), value: hover)
    }
}

// Reusable chrome-free utility surface. Hiding a panel never closes its data store.
class PocketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init(title: String, size: NSSize, resizable: Bool = false) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: resizable ? [.borderless, .resizable] : [.borderless], backing: .buffered, defer: false)
        self.title = title
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        hidesOnDeactivate = true; hasShadow = true; level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }
    override func cancelOperation(_ sender: Any?) { if attachedSheet == nil { orderOut(nil) } }
}
@MainActor enum PanelDismissal {
    static func dismiss(_ windows: [NSWindow?], except clicked: NSWindow? = nil) {
        guard NSApp.modalWindow == nil else { return }
        for window in windows.compactMap({ $0 }) where window.isVisible && window.attachedSheet == nil {
            var ancestor = clicked
            var belongs = false
            while let current = ancestor {
                if current === window { belongs = true; break }
                ancestor = current.parent ?? current.sheetParent
            }
            if !belongs { window.orderOut(nil) }
        }
    }
}
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NoteDragView { NoteDragView() }
    func updateNSView(_ view: NoteDragView, context: Context) {}
}
final class NoteDragView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setFill()
        for offset: CGFloat in [-12, -7, -2, 3, 8, 13] {
            NSBezierPath(ovalIn: NSRect(x: bounds.midX + offset, y: bounds.midY - 1, width: 2, height: 2)).fill()
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
