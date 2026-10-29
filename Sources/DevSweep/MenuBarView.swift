import SwiftUI
import AppKit
import SweepKit

extension ItemKind {
    var title: String {
        switch self {
        case .project: return "Projects"
        case .cache: return "Global Caches"
        case .docker: return "Docker"
        }
    }

    var symbol: String {
        switch self {
        case .project: return "folder"
        case .cache: return "shippingbox"
        case .docker: return "cube"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: SweepModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bubbles.and.sparkles")
            if model.reclaimable >= 1_000_000_000 {
                Text(Bytes.compact(model.reclaimable))
            }
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        if model.diskIsCritical { return .red }
        return model.needsAttention ? .orange : .primary
    }
}

struct MenuBarView: View {
    @ObservedObject var model: SweepModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let disk = model.disk {
                DiskBar(disk: disk)
            }
            Divider()
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubbles.and.sparkles")
                .font(.title2)
                .foregroundStyle(model.needsAttention ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("DevSweep").font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if model.result != nil {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Bytes.format(model.reclaimable))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    Text("reclaimable").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        if model.isScanning {
            guard let progress = model.progress else { return "Scanning…" }
            return "Scanning \(PathDisplay.abbreviate((progress.path as NSString).deletingLastPathComponent, home: model.home))"
        }
        guard let result = model.result else { return "Not scanned yet" }
        return "Scanned \(Format.ago(result.scannedAt)) in \(Format.duration(result.duration))"
    }

    @ViewBuilder
    private var content: some View {
        if model.result == nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.progress.map { "Looked at \($0.folders.formatted(.number.locale(Bytes.locale))) folders, found \($0.found)…" } ?? "Scanning your home folder…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("If macOS asks for access to Desktop, Documents or Downloads, the scan continues once you answer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } else if model.items.isEmpty && !model.isScanning {
            VStack(alignment: .leading, spacing: 4) {
                Label("Nothing to clean", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.green)
                Text("No build folders, caches or Docker leftovers were found.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ItemKind.allCases, id: \.self) { kind in
                        section(kind)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: listHeight)
        }
    }

    private var listHeight: CGFloat {
        var height: CGFloat = 0
        for kind in ItemKind.allCases {
            let count = model.items(kind).count
            let dockerMessage: Bool
            if kind == .docker, case .notRunning = model.result?.docker { dockerMessage = true } else { dockerMessage = false }
            guard count > 0 || dockerMessage else { continue }
            height += 30
            if dockerMessage { height += 18 } else if !model.isCollapsed(kind) { height += CGFloat(count) * 35 }
        }
        return min(520, max(40, height))
    }

    @ViewBuilder
    private func section(_ kind: ItemKind) -> some View {
        let items = model.items(kind)
        if kind == .docker, case .notRunning(let message) = model.result?.docker {
            sectionHeader(kind, items: items)
            Text(message).font(.caption).foregroundStyle(.secondary).padding(.leading, 17)
        } else if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader(kind, items: items)
                if !model.isCollapsed(kind) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items) { item in
                            ItemRow(item: item, model: model)
                        }
                    }
                    .padding(.leading, 17)
                }
            }
        }
    }

    private func sectionHeader(_ kind: ItemKind, items: [Item]) -> some View {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let collapsed = model.isCollapsed(kind)
        return HStack(spacing: 7) {
            Button { model.toggle(kind) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .frame(width: 10)
                    Image(systemName: kind.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(kind.title).font(.system(size: 12, weight: .semibold))
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.16)))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if !items.isEmpty {
                        Text(Bytes.format(total))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !items.isEmpty {
                Toggle("", isOn: Binding(get: { model.allSelected(kind) }, set: { model.setAllSelected(kind, $0) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Select all \(kind.title.lowercased())")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let cleaning = model.cleaning {
                    ProgressView(value: Double(cleaning.done), total: Double(max(cleaning.total, 1)))
                        .frame(width: 120)
                    Text("Cleaning \(min(cleaning.done + 1, cleaning.total)) of \(cleaning.total)…")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button {
                        model.cleanSelected()
                    } label: {
                        Text(model.selection.isEmpty ? "Select items to clean" : "Clean \(Bytes.format(model.selectedSize))")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(model.selectedItems.isEmpty || model.isScanning)
                    Text(selectionSummary)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("Freed so far: \(Bytes.format(model.preferences.totalFreed))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isScanning {
                    Button("Stop") { model.cancelScan() }
                } else {
                    Button("Rescan") { model.scan() }
                }
                Button("Settings…") { SettingsWindow.show() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private var selectionSummary: String {
        let count = model.selectedItems.count
        guard count > 0 else {
            return "Idle projects are preselected after each scan."
        }
        return "\(count) item\(count == 1 ? "" : "s") selected"
    }
}

struct DiskBar: View {
    let disk: DiskSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(color).frame(width: max(4, proxy.size.width * disk.usedFraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Bytes.format(disk.available)) free of \(Bytes.format(disk.total))")
                Spacer()
                Text("\(Int((disk.usedFraction * 100).rounded()))% used")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        if disk.availableFraction < 0.05 { return .red }
        if disk.availableFraction < 0.10 { return .orange }
        return .accentColor
    }
}

struct ItemRow: View {
    let item: Item
    @ObservedObject var model: SweepModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle("", isOn: Binding(get: { model.isSelected(item) }, set: { model.setSelected(item, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if item.kind == .project {
                        Text(item.artifactNames)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Text(Bytes.format(item.size))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(item.size >= 1_000_000_000 ? .primary : .secondary)
        }
        .help("\(item.ecosystem): \(item.restore)")
        .contextMenu {
            if item.kind != .docker {
                Button("Show in Finder") { model.reveal(item) }
                Button("Copy Path") { model.copyPath(item) }
                Divider()
                Button("Exclude from Scans") { model.exclude(item) }
            }
        }
    }

    private var detail: String {
        switch item.kind {
        case .project:
            let idle = item.daysIdle().map(Format.idle) ?? ""
            return [item.location, idle].filter { !$0.isEmpty }.joined(separator: " · ")
        case .cache:
            return "\(item.location) · \(item.restore)"
        case .docker:
            return "\(item.location) · \(item.restore)"
        }
    }
}
