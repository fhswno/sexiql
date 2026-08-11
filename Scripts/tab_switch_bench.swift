import AppKit
import Foundation
import SQLEditor

@main
enum TabSwitchBench {
    static func main() {
        _ = NSApplication.shared

        let ids = (0..<6).map { _ in UUID() }
        var texts: [UUID: String] = [:]
        texts[ids[0]] = "SELECT * FROM users;\n"
        texts[ids[1]] = (0..<2000).map { "SELECT col_\($0) FROM t;\n" }.joined()
        for id in ids.dropFirst(2) {
            texts[id] = String(repeating: "-- line\nSELECT 1;\n", count: 80)
        }

        let host = TabEditorHostView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.syncOpenTabs(ids, texts: texts)
        host.select(ids[0])
        host.layoutSubtreeIfNeeded()

        let warmup = 10
        let rounds = 80
        var samples: [Double] = []
        samples.reserveCapacity(rounds)

        var idx = 0
        for i in 0..<(warmup + rounds) {
            idx = (idx + 1) % ids.count
            let target = ids[idx]
            let t0 = CFAbsoluteTimeGetCurrent()
            host.select(target)
            let t1 = CFAbsoluteTimeGetCurrent()
            if i >= warmup {
                samples.append((t1 - t0) * 1000.0)
            }
        }

        samples.sort()
        let p50 = percentile(samples, 0.50)
        let p95 = percentile(samples, 0.95)
        let maxMs = samples.last ?? 0

        let p95BudgetMs = 8.0
        let p50BudgetMs = 4.0

        print(String(format: "tab_switch_bench select ms: p50=%.3f p95=%.3f max=%.3f", p50, p95, maxMs))
        print("selectTileCount=\(host.selectTileCount) externalHighlightCount=\(host.externalHighlightCount) panes=\(host.paneCount)")

        var failed = false
        if p95 > p95BudgetMs {
            print(String(format: "FAIL: p95 %.3fms > budget %.1fms", p95, p95BudgetMs))
            failed = true
        }
        if p50 > p50BudgetMs {
            print(String(format: "FAIL: p50 %.3fms > budget %.1fms", p50, p50BudgetMs))
            failed = true
        }
        if host.externalHighlightCount > ids.count {
            print("FAIL: unexpected highlights during select (\(host.externalHighlightCount) > \(ids.count))")
            failed = true
        }

        let host2 = TabEditorHostView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        window.contentView = host2
        host2.syncOpenTabs(ids, texts: texts)
        host2.select(ids[0])
        let beforeHL = host2.externalHighlightCount
        var last: UUID? = ids[0]
        var repSamples: [Double] = []
        for i in 0..<rounds {
            let target = ids[i % ids.count]
            let t0 = CFAbsoluteTimeGetCurrent()
            if last != target {
                host2.select(target)
                last = target
            }
            let t1 = CFAbsoluteTimeGetCurrent()
            repSamples.append((t1 - t0) * 1000.0)
        }
        repSamples.sort()
        let rp95 = percentile(repSamples, 0.95)
        print(String(format: "tab_switch_bench representable-select ms: p95=%.3f highlightsDelta=%d", rp95, host2.externalHighlightCount - beforeHL))
        if rp95 > p95BudgetMs {
            print(String(format: "FAIL: representable p95 %.3fms > budget %.1fms", rp95, p95BudgetMs))
            failed = true
        }
        if host2.externalHighlightCount != beforeHL {
            print("FAIL: select path triggered highlight")
            failed = true
        }

        if failed {
            exit(1)
        }
        print("PASS tab_switch_bench")
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[idx]
    }
}
