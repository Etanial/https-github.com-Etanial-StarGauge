//
//  ContentView.swift
//  Star Gauge
//
//  Created by Travis Pierce on 12/13/25.
//

import SwiftUI

// MARK: - Models

struct GridPos: Hashable {
    let r: Int   // 0-based
    let c: Int   // 0-based
}

struct XuanjiGrid {
    let rows: Int
    let cols: Int
    var chars: [[String]] // [r][c]

    func char(at pos: GridPos) -> String {
        guard pos.r >= 0, pos.r < rows, pos.c >= 0, pos.c < cols else { return "" }
        return chars[pos.r][pos.c]
    }
}

// MARK: - CSV Parsing (minimal but handles quoted commas)

enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]

            if ch == "\"" {
                // Toggle quotes; handle escaped quote ("")
                let next = text.index(after: i)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    i = next
                } else {
                    inQuotes.toggle()
                }
            } else if ch == "," && !inQuotes {
                row.append(field)
                field = ""
            } else if (ch == "\n" || ch == "\r") && !inQuotes {
                // Finish field
                if ch == "\r" {
                    // swallow optional \n after \r
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" { i = next }
                }
                row.append(field)
                field = ""
                // only append non-empty rows
                if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    rows.append(row)
                }
                row = []
            } else {
                field.append(ch)
            }

            i = text.index(after: i)
        }

        // last field
        row.append(field)
        if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            rows.append(row)
        }

        return rows
    }
}

// MARK: - Resource Loading

enum ResourceLoader {
    static func loadTextResource(named name: String, ext: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "ResourceLoader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing resource \(name).\(ext) in bundle"
            ])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Build grid from CSV

enum XuanjiGridBuilder {
    /// Supports either:
    /// 1) cell-list: header includes row/col/char, then 841 lines (row/col are 1-based)
    /// 2) row-grid: 29 lines each with 29 comma-separated chars
    static func fromCSVText(_ csvText: String, expectedSize: Int = 29) throws -> XuanjiGrid {
        let table = CSV.parse(csvText)
        guard table.count >= 2 else {
            throw NSError(domain: "XuanjiGridBuilder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "CSV too small"])
        }

        let headerRaw = table[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let header = headerRaw.map { $0.lowercased() }

        func isInt(_ s: String) -> Bool {
            Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        }

        // Header-based detection
        let headerHasRow = header.contains(where: { $0 == "row" || $0 == "r" || $0 == "行" })
        let headerHasCol = header.contains(where: { $0 == "col" || $0 == "c" || $0 == "列" })
        let headerHasChar = header.contains(where: { $0 == "char" || $0 == "ch" || $0 == "zi" || $0 == "字" })

        // Infer cell-list if first *data* row looks like: int,int,something
        let firstData = table[1]
        let inferCellList = firstData.count >= 3 && isInt(firstData[0]) && isInt(firstData[1])

        let useCellList = (headerHasRow && headerHasCol && headerHasChar) || inferCellList

        if useCellList {
            let rIdx = header.firstIndex(where: { $0 == "row" || $0 == "r" || $0 == "行" }) ?? 0
            let cIdx = header.firstIndex(where: { $0 == "col" || $0 == "c" || $0 == "列" }) ?? 1
            let chIdx = header.firstIndex(where: { $0 == "char" || $0 == "ch" || $0 == "zi" || $0 == "字" }) ?? 2

            var grid = Array(repeating: Array(repeating: "", count: expectedSize), count: expectedSize)

            // If header row isn't numeric, skip it; otherwise treat everything as data
            let headerLooksNumeric = table[0].count >= 2 && isInt(table[0][0]) && isInt(table[0][1])
            let dataRows: [[String]] = headerLooksNumeric ? table : Array(table.dropFirst())

            for line in dataRows {
                guard line.count > max(rIdx, cIdx, chIdx) else { continue }
                let r1 = Int(line[rIdx].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let c1 = Int(line[cIdx].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let ch = line[chIdx].trimmingCharacters(in: .whitespacesAndNewlines)

                // Assume CSV is 1-based (r15c15), convert to 0-based
                let r = r1 - 1
                let c = c1 - 1
                if r >= 0, r < expectedSize, c >= 0, c < expectedSize {
                    grid[r][c] = ch
                }
            }

            return XuanjiGrid(rows: expectedSize, cols: expectedSize, chars: grid)
        }

        // Otherwise treat as row-grid
        guard table.count >= expectedSize else {
            throw NSError(domain: "XuanjiGridBuilder", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Row-grid needs \(expectedSize) rows"])
        }

        var grid = Array(repeating: Array(repeating: "", count: expectedSize), count: expectedSize)
        for r in 0..<expectedSize {
            let line = table[r]
            guard line.count >= expectedSize else { continue }
            for c in 0..<expectedSize {
                grid[r][c] = line[c].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return XuanjiGrid(rows: expectedSize, cols: expectedSize, chars: grid)
    }
}

// MARK: - Phrase dictionary (Chinese -> English)

final class PhraseDictionary: ObservableObject {
    @Published private(set) var map: [String: String] = [:]

    func loadFromCSV(named name: String) {
        do {
            let text = try ResourceLoader.loadTextResource(named: name, ext: "csv")
            let table = CSV.parse(text)
            guard table.count >= 2 else { return }

            let header = table[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let zhIdx = header.firstIndex(where: { $0 == "zh" || $0 == "cn" || $0 == "chinese" }) ?? 0
            let enIdx = header.firstIndex(where: { $0 == "en" || $0 == "english" }) ?? 1

            var dict: [String: String] = [:]
            for row in table.dropFirst() {
                guard row.count > max(zhIdx, enIdx) else { continue }
                let zh = row[zhIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                let en = row[enIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                if !zh.isEmpty, !en.isEmpty {
                    dict[zh] = en
                }
            }
            self.map = dict
        } catch {
            // Safe to ignore if you haven't added a phrase CSV yet
            self.map = [:]
        }
    }

    func english(for zh: String) -> String? {
        map[zh]
    }
}

// MARK: - Selection logic (only horizontal/vertical contiguous)

enum SelectionDirection {
    case horizontal, vertical, none
}

func selectionPath(from start: GridPos, to end: GridPos) -> [GridPos] {
    if start.r == end.r {
        let r = start.r
        let lo = min(start.c, end.c)
        let hi = max(start.c, end.c)
        return (lo...hi).map { GridPos(r: r, c: $0) }
    } else if start.c == end.c {
        let c = start.c
        let lo = min(start.r, end.r)
        let hi = max(start.r, end.r)
        return (lo...hi).map { GridPos(r: $0, c: c) }
    } else {
        return [start] // not allowed diagonally; keep just start
    }
}

func selectionDirection(from start: GridPos, to end: GridPos) -> SelectionDirection {
    if start.r == end.r, start.c != end.c { return .horizontal }
    if start.c == end.c, start.r != end.r { return .vertical }
    return .none
}

func selectedChineseString(grid: XuanjiGrid, path: [GridPos], start: GridPos, end: GridPos) -> String {
    // Preserve user direction (L->R vs R->L, T->B vs B->T)
    let dir = selectionDirection(from: start, to: end)
    let ordered: [GridPos]
    switch dir {
    case .horizontal:
        ordered = (start.c <= end.c) ? path : path.reversed()
    case .vertical:
        ordered = (start.r <= end.r) ? path : path.reversed()
    case .none:
        ordered = path
    }
    return ordered.map { grid.char(at: $0) }.joined()
}

// MARK: - View

struct ContentView: View {
    @State private var grid: XuanjiGrid? = nil
    @StateObject private var phrases = PhraseDictionary()

    // Drag selection state
    @State private var startPos: GridPos? = nil
    @State private var currentPos: GridPos? = nil
    @State private var selectedPath: [GridPos] = []

    // UI
    @State private var cellSize: CGFloat = 28
    @State private var showGridLines = true

    // Debug / visibility
    @State private var loadError: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            header

            if let grid {
                gridView(grid)
                selectionPanel(grid)
            } else if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ProgressView("Loading grid…")
                    .task { await load() }
            }
        }
        .padding()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("璇璣圖 Grid")
                    .font(.title2).bold()
                Text("Drag to select 4+ characters horizontally or vertically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Grid", isOn: $showGridLines)
                .toggleStyle(.switch)
        }
    }

    private func gridView(_ grid: XuanjiGrid) -> some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let size = min(cellSize, (totalW - 8) / CGFloat(grid.cols))

            VStack(spacing: 0) {
                ForEach(0..<grid.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<grid.cols, id: \.self) { c in
                            let pos = GridPos(r: r, c: c)
                            let isSelected = selectedPath.contains(pos)
                            let isCenter = (r == 14 && c == 14) // r15c15 in 1-based
                            let ch = grid.chars[r][c]
                            let display = ch.isEmpty ? "·" : ch

                            Text(display)
                                .font(.system(size: size * 0.9, weight: .regular, design: .default))
                                .frame(width: size, height: size)
                                .foregroundStyle(ch.isEmpty ? .secondary : .primary)
                                .background(isSelected ? Color.primary.opacity(0.15) : Color.clear)
                                .overlay {
                                    if showGridLines {
                                        Rectangle()
                                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                                    }
                                }
                                .overlay {
                                    if isCenter {
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5)
                                    }
                                }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pos = posFrom(point: value.location, in: geo.size, rows: grid.rows, cols: grid.cols)
                        guard let pos else { return }

                        if startPos == nil {
                            startPos = pos
                            currentPos = pos
                            selectedPath = [pos]
                        } else {
                            currentPos = pos
                            if let s = startPos {
                                selectedPath = selectionPath(from: s, to: pos)
                            }
                        }
                    }
            )
        }
        .frame(height: 29 * cellSize)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private func selectionPanel(_ grid: XuanjiGrid) -> some View {
        let s = startPos
        let e = currentPos
        let path = selectedPath

        let zh = (s != nil && e != nil) ? selectedChineseString(grid: grid, path: path, start: s!, end: e!) : ""
        let en = phrases.english(for: zh)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selection")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    startPos = nil
                    currentPos = nil
                    selectedPath = []
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chinese")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(zh.isEmpty ? "—" : zh)
                        .font(.system(size: 22, weight: .semibold))
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("English")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(en ?? (zh.count >= 4 ? "No dictionary entry yet." : "Select 4+ characters."))
                        .font(.body)
                        .textSelection(.enabled)
                }
            }

            if zh.count > 0 && zh.count < 4 {
                Text("Tip: select at least 4 characters to match your design rules.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let s, let e {
                Text("Start: r\(s.r+1)c\(s.c+1)  →  End: r\(e.r+1)c\(e.c+1)  |  Length: \(zh.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Coordinate mapping

    private func posFrom(point: CGPoint, in size: CGSize, rows: Int, cols: Int) -> GridPos? {
        let cellW = size.width / CGFloat(cols)
        let effectiveH = CGFloat(rows) * cellSize
        let clampedY = min(max(point.y, 0), effectiveH - 1)

        let c = Int(point.x / cellW)
        let r = Int(clampedY / cellSize)

        guard r >= 0, r < rows, c >= 0, c < cols else { return nil }
        return GridPos(r: r, c: c)
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        do {
            let gridText = try ResourceLoader.loadTextResource(
                named: "xuanji_tu_grid_ctext_trad_tw",
                ext: "csv"
            )
            self.grid = try XuanjiGridBuilder.fromCSVText(gridText, expectedSize: 29)
            phrases.loadFromCSV(named: "xuanji_phrases")
            self.loadError = nil
        } catch {
            self.grid = nil
            self.loadError = "Load failed: \(error.localizedDescription)"
            print("Load error:", error)
        }
    }
}

// MARK: - Xcode Preview (local data so you always see characters)

#if DEBUG
private func makePreviewGrid() -> XuanjiGrid {
    let n = 29
    var g = Array(repeating: Array(repeating: "　", count: n), count: n)

    let samples = Array("天地玄黃宇宙洪荒日月盈昃辰宿列張寒來暑往秋收冬藏")
    for r in 0..<n {
        for c in 0..<n {
            g[r][c] = String(samples[(r * n + c) % samples.count])
        }
    }
    g[14][14] = "心"
    return XuanjiGrid(rows: n, cols: n, chars: g)
}

#Preview("Xuanji Grid - Preview") {
    ContentView_PreviewHost()
        .padding()
}

private struct ContentView_PreviewHost: View {
    @State private var injectedGrid = makePreviewGrid()

    var body: some View {
        VStack(spacing: 12) {
            Text("Preview Host")
                .font(.headline)
            PreviewGridView(grid: injectedGrid)
        }
    }
}

private struct PreviewGridView: View {
    let grid: XuanjiGrid
    @State private var cellSize: CGFloat = 28
    @State private var showGridLines = true

    var body: some View {
        VStack(spacing: 10) {
            Toggle("Grid", isOn: $showGridLines).toggleStyle(.switch)

            GeometryReader { geo in
                let totalW = geo.size.width
                let size = min(cellSize, (totalW - 8) / CGFloat(grid.cols))

                VStack(spacing: 0) {
                    ForEach(0..<grid.rows, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<grid.cols, id: \.self) { c in
                                let isCenter = (r == 14 && c == 14)
                                let ch = grid.chars[r][c]
                                Text(ch.isEmpty ? "·" : ch)
                                    .font(.system(size: size * 0.9))
                                    .frame(width: size, height: size)
                                    .overlay {
                                        if showGridLines {
                                            Rectangle()
                                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                                        }
                                    }
                                    .overlay {
                                        if isCenter {
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2.5)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .frame(height: 29 * cellSize)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
        }
    }
}
#endif


