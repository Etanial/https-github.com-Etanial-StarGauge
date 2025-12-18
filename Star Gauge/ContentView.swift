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
                if ch == "\r" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" { i = next }
                }
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    rows.append(row)
                }
                row = []
            } else {
                field.append(ch)
            }

            i = text.index(after: i)
        }

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

    static func loadDataResource(named name: String, ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "ResourceLoader", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing resource \(name).\(ext) in bundle"
            ])
        }
        return try Data(contentsOf: url)
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

        let headerHasRow = header.contains(where: { $0 == "row" || $0 == "r" || $0 == "行" })
        let headerHasCol = header.contains(where: { $0 == "col" || $0 == "c" || $0 == "列" })
        let headerHasChar = header.contains(where: { $0 == "char" || $0 == "ch" || $0 == "zi" || $0 == "字" })

        let firstData = table[1]
        let inferCellList = firstData.count >= 3 && isInt(firstData[0]) && isInt(firstData[1])

        let useCellList = (headerHasRow && headerHasCol && headerHasChar) || inferCellList

        if useCellList {
            let rIdx = header.firstIndex(where: { $0 == "row" || $0 == "r" || $0 == "行" }) ?? 0
            let cIdx = header.firstIndex(where: { $0 == "col" || $0 == "c" || $0 == "列" }) ?? 1
            let chIdx = header.firstIndex(where: { $0 == "char" || $0 == "ch" || $0 == "zi" || $0 == "字" }) ?? 2

            var grid = Array(repeating: Array(repeating: "", count: expectedSize), count: expectedSize)

            let headerLooksNumeric = table[0].count >= 2 && isInt(table[0][0]) && isInt(table[0][1])
            let dataRows: [[String]] = headerLooksNumeric ? table : Array(table.dropFirst())

            for line in dataRows {
                guard line.count > max(rIdx, cIdx, chIdx) else { continue }
                let r1 = Int(line[rIdx].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let c1 = Int(line[cIdx].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let ch = line[chIdx].trimmingCharacters(in: .whitespacesAndNewlines)

                let r = r1 - 1
                let c = c1 - 1
                if r >= 0, r < expectedSize, c >= 0, c < expectedSize {
                    grid[r][c] = ch
                }
            }

            return XuanjiGrid(rows: expectedSize, cols: expectedSize, chars: grid)
        }

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
            self.map = [:]
        }
    }

    func english(for zh: String) -> String? {
        map[zh]
    }
}

// MARK: - Star Gauge color map (cell_id -> color)

enum StarGaugeColor: String, Codable {
    case red, green, black, purple, yellow

    var background: Color {
        switch self {
        case .red: return .red
        case .green: return .green
        case .black: return .black
        case .purple: return .purple
        case .yellow: return .yellow
        }
    }

    var text: Color {
        switch self {
        case .black, .purple, .red:
            return .white
        default:
            return .black
        }
    }
}

final class StarGaugeColorMap: ObservableObject {
    @Published private(set) var map: [String: StarGaugeColor] = [:]

    func loadFromJSON(named name: String) {
        do {
            let data = try ResourceLoader.loadDataResource(named: name, ext: "json")
            let raw = try JSONDecoder().decode([String: String].self, from: data)

            var out: [String: StarGaugeColor] = [:]
            out.reserveCapacity(raw.count)

            for (k, v) in raw {
                if let c = StarGaugeColor(rawValue: v) {
                    out[k] = c
                }
            }
            self.map = out
        } catch {
            print("Color map load error:", error)
            self.map = [:]
        }
    }

    /// JSON uses keys like "r01c01" ... "r29c29"
    func cellId(r0: Int, c0: Int) -> String {
        String(format: "r%02dc%02d", r0 + 1, c0 + 1)
    }

    func colorFor(r0: Int, c0: Int) -> StarGaugeColor {
        map[cellId(r0: r0, c0: c0)] ?? .yellow
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
        return [start]
    }
}

func selectionDirection(from start: GridPos, to end: GridPos) -> SelectionDirection {
    if start.r == end.r, start.c != end.c { return .horizontal }
    if start.c == end.c, start.r != end.r { return .vertical }
    return .none
}

func selectedChineseString(grid: XuanjiGrid, path: [GridPos], start: GridPos, end: GridPos) -> String {
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

// MARK: - Splash View (UPDATED: shows full image + thinner/smaller/italic link, moved lower)

struct SplashView: View {
    let onExplore: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // A) Always show the full image (no cropping). Letterbox if needed.
                Color.black.ignoresSafeArea()

                Image("splash_guqin")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                Button(action: onExplore) {
                    Text("Explore the Star Gauge")
                        .font(.system(size: 17, weight: .light))
                        .italic()
                        .underline()
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(radius: 6)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                // moved DOWN a little (above her hand area)
                .position(
                    x: geo.size.width * 0.73,
                    y: geo.size.height * 0.40
                )
                .accessibilityLabel("Explore the Star Gauge")
                .accessibilityHint("Opens the Star Gauge grid")
            }
        }
    }
}

// MARK: - Wrapper ContentView (Splash -> Main App)

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
            } else {
                StarGaugeMainView()
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Main App View (UPDATED: grid uses top ~60% with pinch-zoom + pan)

struct StarGaugeMainView: View {
    @State private var grid: XuanjiGrid? = nil
    @StateObject private var phrases = PhraseDictionary()
    @StateObject private var colorMap = StarGaugeColorMap()

    // Selection state
    @State private var startPos: GridPos? = nil
    @State private var currentPos: GridPos? = nil
    @State private var selectedPath: [GridPos] = []

    // UI
    @State private var showGridLines = true
    @State private var loadError: String? = nil

    // Zoom/Pan state
    @State private var gridScale: CGFloat = 1.0
    @State private var gridOffset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var panDrag: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 6.0

    var body: some View {
        GeometryReader { outerGeo in
            let totalH = outerGeo.size.height
            let gridRegionH = totalH * 0.60

            VStack(spacing: 12) {
                header

                if let grid {
                    zoomableGrid(grid)
                        .frame(height: gridRegionH)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
                        )

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("璇璣圖 Grid")
                    .font(.title2).bold()
                Text("Pinch to zoom • Drag to pan • Long-press then drag to select 4+ characters.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Grid", isOn: $showGridLines)
                .toggleStyle(.switch)
        }
    }

    // MARK: - Zoomable grid (top 60% area)

    private func zoomableGrid(_ grid: XuanjiGrid) -> some View {
        GeometryReader { geo in
            let viewport = geo.size
            let side = min(viewport.width, viewport.height)

            // Base cell size so the entire grid is visible initially
            let baseCell = side / CGFloat(grid.cols)
            let baseSide = baseCell * CGFloat(grid.cols)
            let contentSize = CGSize(width: baseSide, height: baseSide)

            // Effective scale/offset (while gesture is active)
            let effectiveScale = clamp(gridScale * pinchScale, minScale, maxScale)

            let proposedOffset = CGSize(
                width: gridOffset.width + panDrag.width,
                height: gridOffset.height + panDrag.height
            )
            let effectiveOffset = clampedOffset(
                proposedOffset,
                scale: effectiveScale,
                viewport: viewport,
                content: contentSize
            )

            // Pan gesture (one finger drag)
            let pan = DragGesture(minimumDistance: 5)
                .updating($panDrag) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let proposed = CGSize(
                        width: gridOffset.width + value.translation.width,
                        height: gridOffset.height + value.translation.height
                    )
                    gridOffset = clampedOffset(proposed, scale: gridScale, viewport: viewport, content: contentSize)
                }

            // Pinch gesture
            let zoom = MagnificationGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    gridScale = clamp(gridScale * value, minScale, maxScale)
                    gridOffset = clampedOffset(gridOffset, scale: gridScale, viewport: viewport, content: contentSize)
                }

            // Selection gesture: long-press then drag (so normal drags pan)
            let select = LongPressGesture(minimumDuration: 0.15)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                .onChanged { seq in
                    switch seq {
                    case .second(true, let drag?):
                        // Convert touch location in the viewport into unscaled/unpanned grid space
                        let p = drag.location
                        let unscaled = CGPoint(
                            x: (p.x - effectiveOffset.width) / effectiveScale,
                            y: (p.y - effectiveOffset.height) / effectiveScale
                        )

                        if let pos = posFrom(point: unscaled, rows: grid.rows, cols: grid.cols, cell: baseCell) {
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

                    default:
                        break
                    }
                }

            ZStack(alignment: .topLeading) {
                // Grid content
                gridContent(grid, cell: baseCell, effectiveScale: effectiveScale, effectiveOffset: effectiveOffset)
                    // Selection uses long-press -> drag; give it priority over pan if it activates
                    .highPriorityGesture(select)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(pan)
            .simultaneousGesture(zoom)
            .onAppear {
                // Center grid initially if we haven’t already positioned it
                if gridOffset == .zero && gridScale == 1.0 {
                    gridOffset = centeredOffset(scale: gridScale, viewport: viewport, content: contentSize)
                }
            }
        }
    }

    private func gridContent(_ grid: XuanjiGrid, cell: CGFloat, effectiveScale: CGFloat, effectiveOffset: CGSize) -> some View {
        let baseSide = cell * CGFloat(grid.cols)

        return VStack(spacing: 0) {
            ForEach(0..<grid.rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<grid.cols, id: \.self) { c in
                        let pos = GridPos(r: r, c: c)
                        let isSelected = selectedPath.contains(pos)
                        let isCenter = (r == 14 && c == 14)
                        let ch = grid.chars[r][c]
                        let display = ch.isEmpty ? "·" : ch

                        let sgColor = colorMap.colorFor(r0: r, c0: c)

                        Text(display)
                            .font(.system(size: cell * 0.9, weight: .regular))
                            .frame(width: cell, height: cell)
                            .foregroundStyle(ch.isEmpty ? .secondary : sgColor.text)
                            .background(sgColor.background)
                            .overlay {
                                if isSelected { Rectangle().fill(Color.white.opacity(0.20)) }
                            }
                            .overlay {
                                if showGridLines {
                                    Rectangle().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                                }
                            }
                            .overlay {
                                if isCenter {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5)
                                }
                            }
                    }
                }
            }
        }
        .frame(width: baseSide, height: baseSide, alignment: .topLeading)
        .scaleEffect(effectiveScale, anchor: .topLeading)
        .offset(effectiveOffset)
    }

    // MARK: - Selection panel (unchanged)

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

    // MARK: - Touch -> grid position mapping (grid local coordinates)

    private func posFrom(point: CGPoint, rows: Int, cols: Int, cell: CGFloat) -> GridPos? {
        let x = point.x
        let y = point.y
        guard x >= 0, y >= 0 else { return nil }

        let c = Int(x / cell)
        let r = Int(y / cell)

        guard r >= 0, r < rows, c >= 0, c < cols else { return nil }
        return GridPos(r: r, c: c)
    }

    // MARK: - Clamp + centering helpers

    private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }

    private func centeredOffset(scale: CGFloat, viewport: CGSize, content: CGSize) -> CGSize {
        let cw = content.width * scale
        let ch = content.height * scale

        let x = (viewport.width - cw) / 2
        let y = (viewport.height - ch) / 2

        // If content is larger than viewport, default to top-left (0,0)
        return CGSize(width: cw <= viewport.width ? x : 0,
                      height: ch <= viewport.height ? y : 0)
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, viewport: CGSize, content: CGSize) -> CGSize {
        let cw = content.width * scale
        let ch = content.height * scale

        let x: CGFloat
        if cw <= viewport.width {
            x = (viewport.width - cw) / 2
        } else {
            let minX = viewport.width - cw
            x = clamp(proposed.width, minX, 0)
        }

        let y: CGFloat
        if ch <= viewport.height {
            y = (viewport.height - ch) / 2
        } else {
            let minY = viewport.height - ch
            y = clamp(proposed.height, minY, 0)
        }

        return CGSize(width: x, height: y)
    }

    // MARK: - Load (unchanged)

    @MainActor
    private func load() async {
        do {
            let gridText = try ResourceLoader.loadTextResource(
                named: "xuanji_tu_grid_ctext_trad_tw",
                ext: "csv"
            )
            self.grid = try XuanjiGridBuilder.fromCSVText(gridText, expectedSize: 29)

            phrases.loadFromCSV(named: "xuanji_phrases")
            colorMap.loadFromJSON(named: "xuanji_tu_cell_colors_v3")

            self.loadError = nil
        } catch {
            self.grid = nil
            self.loadError = "Load failed: \(error.localizedDescription)"
            print("Load error:", error)
        }
    }
}

// MARK: - Preview

#Preview("Star Gauge - Splash then Main") {
    ContentView()
}
