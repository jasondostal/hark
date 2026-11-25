import SwiftUI
import SwiftData
import HarkCore

/// "Removed Mallard · Undo": the one place a removal can be taken back. The data change happens right away (so
/// nothing is lost if iOS kills the app); Undo puts it back. Only the latest removal is undoable; a new one, or
/// five seconds, makes the previous one final.
@MainActor @Observable
final class UndoCenter {
    static let shared = UndoCenter()

    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
        let commit: () -> Void      // runs once the removal can no longer be undone (deletes the clip files)
    }
    private(set) var current: Item?

    func offer(_ message: String, undo: @escaping () -> Void, commit: @escaping () -> Void = {}) {
        current?.commit()
        let item = Item(message: message, undo: undo, commit: commit)
        current = item
        AccessibilityNotification.Announcement("\(message). Undo available.").post()
        Task {
            try? await Task.sleep(for: .seconds(5))
            if current?.id == item.id { finish() }
        }
    }
    func undo() {
        guard let item = current else { return }
        current = nil
        item.undo()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    func finish() {
        guard let item = current else { return }
        current = nil
        item.commit()
    }
}

struct UndoToast: View {
    @State private var center = UndoCenter.shared
    var body: some View {
        Group {
            if let item = center.current {
                HStack(spacing: 14) {
                    Text(item.message).font(.callout).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Undo") { withAnimation { center.undo() } }
                        .font(.callout.bold())
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .padding(.leading, 16).padding(.trailing, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.horizontal, 16)
                .id(item.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: center.current?.id)
    }
}

/// Everything about a logged detection, so a removal can put it back exactly (same id, same clip file).
struct DetectionSnapshot {
    let id: UUID, scientific: String, common: String, group: String
    let confidence: Double, firstHeard: Date, lastHeard: Date, windows: Int
    let latitude: Double?, longitude: Double?, confirmed: Bool, sessionID: UUID, source: String
    let clipFile: String?, isFirst: Bool

    init(_ d: Detection) {
        id = d.id; scientific = d.scientific; common = d.common; group = d.group
        confidence = d.confidence; firstHeard = d.firstHeard; lastHeard = d.lastHeard; windows = d.windows
        latitude = d.latitude; longitude = d.longitude; confirmed = d.confirmed; sessionID = d.sessionID; source = d.source
        clipFile = d.clipFile; isFirst = d.isFirst
    }

    @MainActor func restore(in ctx: ModelContext) -> Detection {
        let label = HarkCore.Label(scientific: scientific, common: common, group: TaxonGroup(rawValue: group) ?? .unknown)
        let d = Detection(id: id, label: label, confidence: confidence, at: firstHeard, windows: windows,
                          latitude: latitude, longitude: longitude, sessionID: sessionID, source: source)
        d.common = common; d.group = group      // exactly as stored, whatever the label table says today
        d.lastHeard = lastHeard; d.confirmed = confirmed; d.clipFile = clipFile; d.isFirst = isFirst
        ctx.insert(d)
        return d
    }
}

/// Delete from the store now; the clip file stays until the removal is final, so Undo can bring it back.
@MainActor func removeDetections(_ ds: [Detection], in ctx: ModelContext) -> (snapshots: [DetectionSnapshot], commit: () -> Void) {
    let snaps = ds.map(DetectionSnapshot.init)
    for d in ds {
        if ClipPlayer.shared.playingID == d.clipFile { ClipPlayer.shared.stop() }
        ctx.delete(d)
    }
    try? ctx.save()
    WidgetBridge.refresh(ctx, listening: Listener.shared.state == .listening)
    let files = snaps.compactMap(\.clipFile)
    return (snaps, { files.forEach { ClipStore.delete($0) } })
}

/// Delete one row from the Journal, with Undo.
@MainActor func deleteWithUndo(_ d: Detection, in ctx: ModelContext) {
    let name = d.displayName
    let (snaps, commit) = removeDetections([d], in: ctx)
    UndoCenter.shared.offer("Deleted \(name)", undo: {
        snaps.forEach { _ = $0.restore(in: ctx) }
        try? ctx.save()
        WidgetBridge.refresh(ctx, listening: Listener.shared.state == .listening)
    }, commit: commit)
}
