import SwiftUI

/// Write or edit one diary entry. The mood chips are the tag shown next to the
/// date in the feed.
struct EntryComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    let author: DiaryAuthor
    let existing: DiaryEntry?
    var onSaved: () async -> Void

    @State private var body_ = ""
    @State private var mood: String?
    @State private var isSaving = false
    /// Set after saving a new entry, which hands off to the extraction sheet
    /// instead of dismissing straight away.
    @State private var justSaved: DiaryEntry?
    @FocusState private var focused: Bool

    private static let moods = ["累了", "开心", "平静", "烦躁", "想他", "有劲"]

    var body: some View {
        ZStack {
            SkinBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("取消") { dismiss() }
                    Spacer()
                    Text(existing == nil ? "写日记" : "编辑")
                        .font(.display(16, weight: .medium))
                    Spacer()
                    Button(isSaving ? "保存中" : "保存", action: save)
                        .fontWeight(.medium)
                        .disabled(!canSave || isSaving)
                }
                .font(.system(size: 15))
                .foregroundStyle(theme.onBackground)

                moodRow

                TextEditor(text: $body_)
                    .font(.system(size: 16))
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(theme.onBackground)
                    .focused($focused)
                    .frame(maxHeight: .infinity)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.cardColor.opacity(theme.cardOpacity)))
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("今天…")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.secondaryOnBackground)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                if existing != nil {
                    Button(role: .destructive, action: delete) {
                        Label("删除这篇", systemImage: "trash").font(.system(size: 14))
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            body_ = existing?.body ?? ""
            mood = existing?.mood
            focused = existing == nil
        }
        .sheet(item: $justSaved) { entry in
            TodoExtractionSheet(entry: entry) { await onSaved() }
                .onDisappear { dismiss() }
        }
    }

    private var moodRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Self.moods, id: \.self) { option in
                    let selected = mood == option
                    Button {
                        mood = selected ? nil : option
                    } label: {
                        Text(option)
                            .font(.system(size: 12))
                            .foregroundStyle(selected ? .white : theme.onBackground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(selected
                                ? AnyShapeStyle(theme.accent)
                                : AnyShapeStyle(theme.onBackground.opacity(0.08))))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var canSave: Bool { !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func save() {
        isSaving = true
        Task {
            if let existing {
                _ = try? await model.api.updateDiary(id: existing.id, mood: mood, body: body_)
                await onSaved()
                isSaving = false
                dismiss()
            } else {
                let created = try? await model.api.createDiary(
                    author: author, date: DateOnly.today, mood: mood, body: body_)
                await onSaved()
                isSaving = false
                // A fresh entry is the one worth mining for todos; an edit is not.
                if let created { justSaved = created } else { dismiss() }
            }
        }
    }

    private func delete() {
        guard let existing else { return }
        Task {
            try? await model.api.deleteDiary(id: existing.id)
            await onSaved()
            dismiss()
        }
    }
}
