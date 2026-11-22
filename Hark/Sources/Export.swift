import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HarkCore

/// A detection flattened for sharing and export (SwiftData models stay on the main actor).
struct ExportRow: Sendable {
    let name: String, common: String, scientific: String, nickname: String?, group: String
    let firstHeard: Date, lastHeard: Date, percent: Int, confirmed: Bool, source: String
    let latitude: Double?, longitude: Double?, session: UUID

    @MainActor init(_ d: Detection) {
        name = d.displayName; common = d.common; scientific = d.scientific; nickname = NameBook.shared.nickname(d.scientific)
        group = d.group; firstHeard = d.firstHeard; lastHeard = d.lastHeard; percent = d.confidence.shownPercent
        confirmed = d.confirmed; source = d.source; latitude = d.latitude; longitude = d.longitude; session = d.sessionID
    }
}

private func exportFolder() throws -> URL {
    let dir = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
private func fileStamp(_ d: Date) -> String { d.formatted(.iso8601.year().month().day()) }

// MARK: Spreadsheet

struct CSVExport: Transferable {
    let rows: [ExportRow]
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { e in SentTransferredFile(try e.write()) }
    }
    func write() throws -> URL {
        func q(_ s: String) -> String { s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        var out = "first_heard,last_heard,common_name,scientific_name,nickname,group,confidence_percent,confirmed,how,latitude,longitude,session\n"
        for r in rows.sorted(by: { $0.firstHeard < $1.firstHeard }) {
            out += [iso.string(from: r.firstHeard), iso.string(from: r.lastHeard), q(r.common), q(r.scientific), q(r.nickname ?? ""), r.group,
                    "\(r.percent)", r.confirmed ? "yes" : "no", r.source,
                    r.latitude.map { String(format: "%.5f", $0) } ?? "", r.longitude.map { String(format: "%.5f", $0) } ?? "",
                    r.session.uuidString].joined(separator: ",") + "\n"
        }
        let url = try exportFolder().appending(path: "Hark log \(fileStamp(.now)).csv")
        try out.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: PDF field report

/// A printable report: a species summary (most heard first), then every detection in order.
/// Locations are left out so it's safe to pass around; the spreadsheet has them.
struct PDFExport: Transferable {
    let rows: [ExportRow]
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { e in SentTransferredFile(try e.write()) }
    }

    func write() throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792), margin: CGFloat = 50
        let url = try exportFolder().appending(path: "Hark report \(fileStamp(.now)).pdf")
        let sorted = rows.sorted { $0.firstHeard < $1.firstHeard }
        let species = Dictionary(grouping: rows, by: \.scientific).values
            .map { ds in (ds[0], ds.count, ds.contains(where: \.confirmed), ds.map(\.firstHeard).min()!) }
            .sorted { ($0.1, $1.0.name) > ($1.1, $0.0.name) }

        let ink = UIColor(red: 0.12, green: 0.10, blue: 0.20, alpha: 1), soft = UIColor(white: 0.42, alpha: 1)
        let accent = UIColor(red: 0.25, green: 0.70, blue: 0.50, alpha: 1)
        func font(_ s: CGFloat, _ w: UIFont.Weight = .regular) -> UIFont { UIFont.systemFont(ofSize: s, weight: w) }
        func italic(_ s: CGFloat) -> UIFont { UIFont.italicSystemFont(ofSize: s) }

        try UIGraphicsPDFRenderer(bounds: page).writePDF(to: url) { ctx in
            var y: CGFloat = 0
            var pageNo = 0
            func newPage() {
                ctx.beginPage(); pageNo += 1; y = margin
                let foot = NSAttributedString(string: "Hark · page \(pageNo)", attributes: [.font: font(8), .foregroundColor: soft])
                foot.draw(at: CGPoint(x: margin, y: page.height - margin + 16))
            }
            func need(_ h: CGFloat) { if y + h > page.height - margin { newPage() } }
            func text(_ s: String, _ f: UIFont, _ c: UIColor? = nil, x xo: CGFloat? = nil, width: CGFloat? = nil) {
                let x = xo ?? margin
                NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c ?? ink])
                    .draw(with: CGRect(x: x, y: y, width: width ?? page.width - margin - x, height: 40),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
            func rule() {
                let p = UIBezierPath(); p.move(to: CGPoint(x: margin, y: y)); p.addLine(to: CGPoint(x: page.width - margin, y: y))
                UIColor(white: 0.85, alpha: 1).setStroke(); p.lineWidth = 0.5; p.stroke()
            }

            newPage()
            text("Hark field report", font(24, .bold)); y += 32
            let span: String = {
                guard let a = sorted.first?.firstHeard, let b = sorted.last?.lastHeard else { return "" }
                let f = Date.FormatStyle(date: .abbreviated, time: .omitted)
                return a.formatted(f) == b.formatted(f) ? a.formatted(f) : "\(a.formatted(f)) to \(b.formatted(f))"
            }()
            text("\(span) · \(species.count) species · \(rows.count) detections · \(rows.filter(\.confirmed).count) seen", font(11), soft); y += 28

            text("Species", font(14, .semibold), accent); y += 22
            for (r, n, seen, first) in species {
                need(30)
                text(r.name, font(11, .semibold), width: 280)
                text("\(n)×", font(11).withMonospacedDigits(), x: margin + 290, width: 50)
                text(first.formatted(date: .abbreviated, time: .omitted), font(10), soft, x: margin + 340, width: 110)
                if seen { text("seen", font(10, .semibold), accent, x: margin + 460, width: 50) }
                y += 14
                let other = r.nickname != nil ? "\(r.common) · \(r.scientific)" : (r.scientific == r.name ? r.common : r.scientific)
                text(other, r.nickname == nil && r.scientific != r.name ? italic(9) : font(9), soft, width: 280)
                y += 15; rule(); y += 5
            }

            y += 16; need(60)
            text("Every detection", font(14, .semibold), accent); y += 22
            var day = ""
            for r in sorted {
                let d = r.firstHeard.formatted(date: .complete, time: .omitted)
                if d != day { need(40); day = d; y += 4; text(d, font(10, .semibold), soft); y += 16 }
                need(16)
                text(r.firstHeard.formatted(date: .omitted, time: .shortened), font(10).withMonospacedDigits(), soft, width: 60)
                text(r.name, font(10, .medium), x: margin + 64, width: 260)
                text("\(r.percent)%", font(10).withMonospacedDigits(), soft, x: margin + 330, width: 40)
                let how = r.source == "live" ? "" : "by hand"
                text([r.confirmed ? "seen" : "", how].filter { !$0.isEmpty }.joined(separator: " · "), font(9), soft, x: margin + 380, width: 130)
                y += 15
            }
        }
        return url
    }
}

extension UIFont {
    func withMonospacedDigits() -> UIFont {
        UIFont(descriptor: fontDescriptor.addingAttributes([.featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                                                                 UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]]]),
               size: pointSize)
    }
}

/// Log toolbar: share what's shown (the current filter) as a PDF report or a spreadsheet.
struct LogExportMenu: View {
    let detections: [Detection]
    var body: some View {
        let rows = detections.map(ExportRow.init)
        Menu {
            ShareLink(item: PDFExport(rows: rows), preview: SharePreview("Hark field report", image: Image(systemName: "doc.richtext"))) {
                Label("Field report (PDF)", systemImage: "doc.richtext")
            }
            ShareLink(item: CSVExport(rows: rows), preview: SharePreview("Hark log", image: Image(systemName: "tablecells"))) {
                Label("Spreadsheet (CSV)", systemImage: "tablecells")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(detections.isEmpty)
        .accessibilityLabel("Share the log")
    }
}

// MARK: One detection

/// Detection page: opens the share card (preview, location choice, recording) and then the share sheet.
struct DetectionShareButton: View {
    let detection: Detection
    @State private var show = ProcessInfo.processInfo.arguments.contains("-sharecard")   // screenshot aid
    var body: some View {
        Button { show = true } label: { Image(systemName: "square.and.arrow.up") }
            .accessibilityLabel("Share")
            .sheet(isPresented: $show) { ShareCardSheet(detection: detection).themeRoot() }
    }
}
