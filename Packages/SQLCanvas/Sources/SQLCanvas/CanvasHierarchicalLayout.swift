public enum CanvasHierarchicalLayout {
    struct Node {
        var id: String
        var rank: Int
        var height: Double
    }

    public static func arrange(tables: [CanvasTable], edges: [CanvasEdge]) -> [CanvasTable] {
        guard !tables.isEmpty else { return tables }
        let byID = Dictionary(uniqueKeysWithValues: tables.map { ($0.id, $0) })

        var children: [String: [String]] = [:]
        var parents: [String: [String]] = [:]
        var seenPairs = Set<String>()
        for edge in edges {
            let parent = edge.toTableID
            let child = edge.fromTableID
            guard parent != child, byID[parent] != nil, byID[child] != nil else { continue }
            if seenPairs.insert("\(parent)->\(child)").inserted {
                children[parent, default: []].append(child)
                parents[child, default: []].append(parent)
            }
        }

        func height(of id: String) -> Double {
            guard let table = byID[id] else { return CanvasCardMetrics.headerHeight }
            return CanvasCardMetrics.tableHeight(columnCount: table.columns.count)
        }

        // MARK: Rank Assignment

        var rank: [String: Int] = [:]
        var inStack = Set<String>()

        func computeRank(_ id: String, depth: Int) -> Int {
            if let known = rank[id] { return known }
            if inStack.contains(id) || depth > tables.count + 1 { return 0 }
            inStack.insert(id)
            defer { inStack.remove(id) }
            let parentRanks = (parents[id] ?? []).map { computeRank($0, depth: depth + 1) }
            let computed = (parentRanks.max().map { $0 + 1 }) ?? 0
            rank[id] = computed
            return computed
        }
        for table in tables {
            _ = computeRank(table.id, depth: 0)
        }

        let maxRank = rank.values.max() ?? 0
        var idsByRank: [Int: [String]] = [:]
        for table in tables {
            idsByRank[rank[table.id] ?? 0, default: []].append(table.id)
        }
        for key in idsByRank.keys {
            idsByRank[key]?.sort { $0 < $1 }
        }

        // MARK: Within-Rank Ordering

        var order: [Int: [String]] = idsByRank
        var ordinals: [String: Int] = [:]
        for key in order.keys {
            for (index, id) in order[key]!.enumerated() {
                ordinals[id] = index
            }
        }

        func median(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        }

        for sweep in 0..<4 {
            let downward = sweep % 2 == 0
            let ranks = downward ? Array(0...maxRank) : Array(stride(from: maxRank, through: 0, by: -1))
            for r in ranks {
                guard let current = order[r], !current.isEmpty else { continue }
                let neighborMap = downward ? parents : children
                let neighborRank = downward ? r - 1 : r + 1
                var keyed: [(id: String, key: Double)] = []
                for id in current {
                    let neighborOrdinals = (neighborMap[id] ?? []).compactMap { neighbor -> Double? in
                        guard rank[neighbor] == neighborRank, let ordinal = ordinals[neighbor] else { return nil }
                        return Double(ordinal)
                    }
                    keyed.append((id: id, key: median(neighborOrdinals)))
                }
                keyed.sort {
                    if $0.key != $1.key { return $0.key < $1.key }
                    return $0.id < $1.id
                }
                order[r] = keyed.map(\.id)
                for (index, id) in keyed.map(\.id).enumerated() {
                    ordinals[id] = index
                }
            }
        }

        // MARK: Initial Packing

        var positions: [String: CanvasPoint] = [:]
        let rankGap = 110.0
        let rowGap = 56.0
        let x0 = 40.0

        for r in 0...maxRank {
            guard let idsInRank = order[r] else { continue }
            var y = 40.0
            for id in idsInRank {
                positions[id] = CanvasPoint(x: x0 + Double(r) * (CanvasCardMetrics.cardWidth + rankGap), y: y)
                y += height(of: id) + rowGap
            }
        }

        // MARK: Coordinate Relaxation

        let neighborSets: [String: (up: [String], down: [String])] = {
            var result: [String: (up: [String], down: [String])] = [:]
            for id in byID.keys {
                result[id] = (parents[id] ?? [], children[id] ?? [])
            }
            return result
        }()

        for pass in 0..<6 {
            let downward = pass % 2 == 0
            let ranks = downward ? Array(0...maxRank) : Array(stride(from: maxRank, through: 0, by: -1))
            for r in ranks {
                guard let idsInRank = order[r], idsInRank.count > 1 else { continue }
                if downward {
                    var previousBottom: Double?
                    for id in idsInRank {
                        let h = height(of: id)
                        let neighbors = neighborSets[id] ?? ([], [])
                        let centers = (neighbors.up + neighbors.down).compactMap { neighbor -> Double? in
                            positions[neighbor].map { $0.y + height(of: neighbor) / 2 }
                        }
                        let desired = median(centers) - h / 2
                        let y = max(desired, previousBottom.map { $0 + rowGap } ?? desired)
                        positions[id] = CanvasPoint(x: positions[id]!.x, y: y)
                        previousBottom = y + h
                    }
                } else {
                    var previousTop: Double?
                    for id in idsInRank.reversed() {
                        let h = height(of: id)
                        let neighbors = neighborSets[id] ?? ([], [])
                        let centers = (neighbors.up + neighbors.down).compactMap { neighbor -> Double? in
                            positions[neighbor].map { $0.y + height(of: neighbor) / 2 }
                        }
                        let desired = median(centers) - h / 2
                        let y = min(desired, previousTop.map { $0 - rowGap - h } ?? desired)
                        positions[id] = CanvasPoint(x: positions[id]!.x, y: y)
                        previousTop = y
                    }
                }
            }
        }

        // MARK: Global Normalize
        var globalMin = Double.greatestFiniteMagnitude
        for id in byID.keys {
            guard let position = positions[id] else { continue }
            globalMin = min(globalMin, position.y)
        }
        if globalMin.isFinite {
            let shift = 40.0 - globalMin
            if shift != 0 {
                for id in byID.keys {
                    if var position = positions[id] {
                        position.y += shift
                        positions[id] = position
                    }
                }
            }
        }

        return byID.keys.sorted().compactMap { id in
            guard var positioned = byID[id] else { return nil }
            positioned.position = positions[id] ?? positioned.position
            return positioned
        }
    }
}
