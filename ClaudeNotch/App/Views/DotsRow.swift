import AppKit
import SwiftUI
import ClaudeNotchKit

/// The dots in the closed wing: one per slot in a two-row grid, columns
/// filled top to bottom, plus a "+N" when more sessions exist than slots.
/// Empty slots keep their space so positions never shift.
struct DotsGrid: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        let columns = WingLayout.columns(store.slotted)
        HStack(spacing: WingLayout.gap) {
            ForEach(columns.indices, id: \.self) { c in
                VStack(spacing: WingLayout.gap) {
                    ForEach(columns[c].indices, id: \.self) { r in
                        let session = columns[c][r]
                        SessionDot(session: session,
                                   acknowledged: session.map { store.isAcknowledged($0.id) } ?? true,
                                   size: WingLayout.dot)
                            .contentShape(Rectangle().inset(by: -2.5))
                            .onTapGesture {
                                if let session { NotchCoordinator.shared.select(session) }
                            }
                    }
                }
            }
            if !store.overflow.isEmpty {
                Text("+\(store.overflow.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: WingLayout.overflowWidth, alignment: .leading)
                    .accessibilityLabel("\(store.overflow.count) more sessions")
            }
        }
        .animation(.smooth(duration: 0.25), value: columns.count)
    }
}

/// A single status dot. Red and unacknowledged: it pulses. Done and idle
/// (Claude has been waiting a while): it breathes slowly. With Reduce Motion
/// on, the red dot gets a ring instead of a pulse. The circle and its motion
/// are Core Animation (`DotLayer`), so a dot that moves for hours costs no
/// CPU.
struct SessionDot: View {
    let session: Session?
    let acknowledged: Bool
    var size: CGFloat = 8

    @EnvironmentObject private var store: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: DotLayer.Motion {
        guard let session, !reduceMotion else { return .still }
        if session.state == .needsYou && !acknowledged { return .pulse }
        if session.state == .done && session.idle { return .breathe }
        return .still
    }

    private var ringed: Bool {
        guard let session else { return false }
        return session.state == .needsYou && !acknowledged && reduceMotion
    }

    var body: some View {
        ZStack {
            if let session {
                DotLayer(color: NSColor(session.state.color), motion: motion, size: size)
                    .frame(width: size, height: size)
                    .overlay {
                        if ringed {
                            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                                .frame(width: size + 6, height: size + 6)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(store.projectName(of: session)) \(session.state.announcement)")
            }
        }
        .frame(width: size, height: size)
    }
}
