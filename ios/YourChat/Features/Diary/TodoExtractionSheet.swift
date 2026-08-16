import SwiftUI

/// After a diary entry is saved, the AI reads it back and proposes the things
/// in it that still need doing. Nothing is created until you tick it — the
/// relay's extract endpoint only ever returns candidates.
struct TodoExtractionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    let entry: DiaryEntry
    var onAdded: () async -> Void

    @State private var candidates: [String] = []
    @State private var selected: Set<String> = []
    @State private var source = ""
    @State private var phase: Phase = .reading

    private enum Phase {
        case reading
        case ready
        case none
        case adding
    }

    var body: some View {
        ZStack {
            SkinBackground()

            VStack(alignment: .leading, spacing: 16) {
                header

                switch phase {
                case .reading:
                    status("正在读这篇日记…", spinner: true)
                case .none:
                    status("这篇里没有需要跟进的事。", spinner: false)
                case .ready, .adding:
                    list
                }

                Spacer()

                if phase == .ready || phase == .adding {
                    Button(action: add) {
                        Text(selected.isEmpty ? "不用了" : "添加 \(selected.count) 条")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(
                                selected.isEmpty ? theme.secondaryOnBackground : theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(phase == .adding)
                }
            }
            .padding(20)
        }
        .presentationDetents([.medium])
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("从这篇提取待办")
                    .font(.display(20, weight: .semibold))
                    .foregroundStyle(theme.onBackground)
                if !source.isEmpty {
                    Text(source)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
            }
            Spacer()
            Button("跳过") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(theme.secondaryOnBackground)
        }
    }

    private func status(_ text: String, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().controlSize(.small) }
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryOnBackground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(candidates, id: \.self) { candidate in
                Button {
                    if selected.contains(candidate) { selected.remove(candidate) }
                    else { selected.insert(candidate) }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: selected.contains(candidate)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19))
                            .foregroundStyle(selected.contains(candidate)
                                             ? theme.accent : theme.onBackground.opacity(0.3))
                        Text(candidate)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.onBackground)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func load() async {
        do {
            let result = try await model.api.extractTodos(fromDiary: entry.id)
            source = result.source
            candidates = result.candidates
            // Pre-ticked: the common case is "yes, all of those".
            selected = Set(result.candidates)
            phase = result.candidates.isEmpty ? .none : .ready
        } catch {
            phase = .none
        }
    }

    private func add() {
        guard !selected.isEmpty else { return dismiss() }
        phase = .adding
        Task {
            // Ordered by the AI's list, not by Set iteration order.
            for candidate in candidates where selected.contains(candidate) {
                _ = try? await model.api.createTodo(
                    owner: entry.author, title: candidate, source: source)
            }
            await onAdded()
            dismiss()
        }
    }
}
