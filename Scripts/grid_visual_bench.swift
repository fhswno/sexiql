import AppKit
import Foundation
import SQLDrivers
import SQLGrid

@main
enum GridVisualBench {
    static func main() {
        _ = NSApplication.shared
        var failed = false
        func check(_ c: Bool, _ m: String) {
            if !c { print("FAIL: \(m)"); failed = true }
        }

        let host = ResultGridScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)

        let columns = [
            GridColumn(ordinal: 0, name: "id", dataType: "INTEGER"),
            GridColumn(ordinal: 1, name: "name", dataType: "TEXT"),
            GridColumn(ordinal: 2, name: "email", dataType: "TEXT"),
        ]
        let row = SQLRow(values: [
            .int(1),
            .string("David Ohayon"),
            .string("dave@openswing.dev"),
        ])
        host.grid.setModel(ResultSetModel(columns: columns, rows: [row], totalRowCount: 1, isComplete: true))
        host.layoutSubtreeIfNeeded()
        host.tile()
        host.pinDocument()

        let grid = host.grid
        let ids = grid.columnIdentifiers
        let headers = grid.labeledHeaderTitles

        print("columns: \(ids)")
        print("headers: \(headers.joined(separator: " | "))")
        print(String(
            format: "headerH=%.0f rows=%d docIsTable=%@ emailW=%.0f",
            grid.headerView?.frame.height ?? -1,
            grid.visibleRowCount,
            String(describing: host.documentView === grid),
            grid.tableColumns.last(where: { $0.identifier.rawValue.hasPrefix("col-") })?.width ?? -1
        ))

        check(host.documentView === grid, "table must be documentView")
        check(grid.headerView != nil, "headerView must exist")
        check((grid.headerView?.frame.height ?? 0) >= 20, "header height missing")
        check(ids == ["row-index", "col-0", "col-1", "col-2"], "ids \(ids)")
        check(!ids.contains("spacer") && !ids.contains("filler"), "no spacer/filler")
        check(grid.visibleRowCount == 1, "one row")
        check(headers.count == 4, "4 headers")
        check(headers.contains(where: { $0.contains("#") }), "# header")
        check(headers.contains(where: { $0.contains("id") }), "id header")
        check(headers.contains(where: { $0.contains("name") }), "name header")
        check(headers.filter { $0.lowercased().contains("email") }.count == 1, "one email header")

        // Rasterize header — must not be blank
        if let header = grid.headerView,
           let rep = header.bitmapImageRepForCachingDisplay(in: header.bounds) {
            header.cacheDisplay(in: header.bounds, to: rep)
            var painted = 0
            for y in 0..<min(rep.pixelsHigh, 32) {
                for x in 0..<min(rep.pixelsWide, 300) {
                    var px = [Int](repeating: 0, count: 4)
                    rep.getPixel(&px, atX: x, y: y)
                    if px[0] + px[1] + px[2] > 40 { painted += 1 }
                }
            }
            print("header raster painted=\(painted)")
            check(painted > 100, "header blank when rasterized (\(painted))")
        }

        if failed {
            print("FAIL grid_visual_bench")
            exit(1)
        }
        print("PASS grid_visual_bench")
    }
}
