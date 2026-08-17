import SwiftUI

/// Two diaries, a shared to-do card, a month grid with a dot on every day that
/// has an entry, and the entries themselves.
struct DiaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    @State private var author: DiaryAuthor = .user
    @State private var entries: [DiaryEntry] = []
    @State private var todos: [TodoItem] = []
    @State private var marks: [String: Int] = [:]
    @State private var visibleMonth = Date()
    @State private var showsCalendar = true
    @State private var composing = false
    @State private var editing: DiaryEntry?
    @State private var searching = false

    var body: some View {
        VStack(spacing: 0) {
            header
            picker

            ScrollView {
                VStack(spacing: 14) {
                    TodoCard(author: author, todos: $todos, onChange: loadTodos)

                    if showsCalendar {
                        MonthCalendar(month: $visibleMonth, marks: marks)
                            .card(padding: 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    entryFeed
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .task(id: author) { await reload() }
        .task(id: DateOnly.month(from: visibleMonth)) { await loadMarks() }
        .sheet(isPresented: $composing) {
            EntryComposer(author: author, existing: nil) { await reload() }
        }
        .sheet(item: $editing) { entry in
            EntryComposer(author: author, existing: entry) { await reload() }
        }
        .sheet(isPresented: $searching) { SearchView() }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text("Diary")
                .font(.display(30, weight: .semibold))
                .foregroundStyle(theme.onBackground)

            Spacer()

            Button { searching = true } label: {
                icon("magnifyingglass", filled: false)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.smooth(duration: 0.3)) { showsCalendar.toggle() }
            } label: {
                icon("calendar", filled: showsCalendar)
            }
            .buttonStyle(.plain)

            Button { composing = true } label: {
                icon("square.and.pencil", filled: true, inverted: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func icon(_ name: String, filled: Bool, inverted: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(inverted ? .white : theme.onBackground.opacity(filled ? 1 : 0.45))
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(inverted
                              ? AnyShapeStyle(Color(hex: 0x1A1A1A))
                              : AnyShapeStyle(theme.cardColor.opacity(theme.cardOpacity))))
    }

    private var picker: some View {
        HStack(spacing: 0) {
            ForEach(DiaryAuthor.allCases) { option in
                let title = option == .user
                    ? (model.profile.userName.isEmpty ? "我" : model.profile.userName)
                    : model.profile.aiAName
                Button {
                    withAnimation(.smooth(duration: 0.25)) { author = option }
                } label: {
                    Text(title)
                        .font(.display(15, weight: author == option ? .semibold : .regular))
                        .foregroundStyle(author == option ? .white : theme.onBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(author == option
                                           ? AnyShapeStyle(Color(hex: 0x1A1A1A))
                                           : AnyShapeStyle(Color.clear)))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.cardColor.opacity(theme.cardOpacity)))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Entries

    @ViewBuilder
    private var entryFeed: some View {
        if entries.isEmpty {
            Text(author == .user ? "还没有日记。" : "\(model.profile.aiAName) 还没有写。")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryOnBackground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 20)
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(entries) { entry in
                    DiaryEntryRow(entry: entry)
                        .contentShape(.rect)
                        .onTapGesture { if author == .user { editing = entry } }
                }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Loading

    private func reload() async {
        entries = (try? await model.api.diary(author: author)) ?? []
        await loadMarks()
        loadTodos()
    }

    private func loadMarks() async {
        marks = (try? await model.api.diaryMarks(
            author: author, month: DateOnly.month(from: visibleMonth))) ?? [:]
    }

    private func loadTodos() {
        Task { todos = (try? await model.api.todos(owner: author)) ?? [] }
    }
}

/// One entry: date, mood tag, body.
struct DiaryEntryRow: View {
    @Environment(ThemeStore.self) private var theme
    let entry: DiaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(theme.onBackground.opacity(0.6), lineWidth: 1.4)
                    .frame(width: 9, height: 9)

                Text(headline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.onBackground)

                if let mood = entry.mood, !mood.isEmpty {
                    Text(mood)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryOnBackground)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.onBackground.opacity(0.08)))
                }
            }

            Text(entry.body)
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(theme.onBackground.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 17)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        guard let date = entry.day else { return entry.date }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }
}
