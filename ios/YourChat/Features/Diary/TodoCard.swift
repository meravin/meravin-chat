import SwiftUI

/// "Today's To Do" — three at a time with paging dots, a quick-add field, and a
/// long-press menu to schedule or delete.
struct TodoCard: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    let author: DiaryAuthor
    @Binding var todos: [TodoItem]
    var onChange: () -> Void

    @State private var draft = ""
    @State private var page = 0

    private let perPage = 3

    private var pages: [[TodoItem]] {
        let open = todos.sorted { !$0.isDone && $1.isDone }
        return stride(from: 0, to: max(open.count, 1), by: perPage).map {
            Array(open[$0..<min($0 + perPage, open.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(todayHeadline)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryOnBackground)
                .frame(maxWidth: .infinity)

            HStack {
                Text("Today's To Do")
                    .font(.display(21, weight: .semibold))
                    .foregroundStyle(theme.onBackground)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryOnBackground)
            }

            if todos.isEmpty {
                Text("今天还没有安排。")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryOnBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, group in
                        VStack(spacing: 0) {
                            ForEach(group) { todo in row(todo) }
                            Spacer(minLength: 0)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: CGFloat(perPage) * 46)

                if pages.count > 1 { dots }
            }

            quickAdd
        }
        .card()
    }

    private var todayHeadline: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, EEEE"
        return f.string(from: Date())
    }

    private var dots: some View {
        HStack(spacing: 5) {
            Spacer()
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(theme.onBackground.opacity(index == page ? 0.7 : 0.2))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        HStack(spacing: 11) {
            Button {
                Task {
                    _ = try? await model.api.updateTodo(
                        id: todo.id, state: todo.isDone ? .pending : .done)
                    onChange()
                }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(todo.isDone ? theme.accent : theme.onBackground.opacity(0.3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(todo.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.onBackground.opacity(todo.isDone ? 0.4 : 1))
                    .strikethrough(todo.isDone, color: theme.secondaryOnBackground)
                    .lineLimit(1)

                if let source = todo.source {
                    Text(source)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
            }

            Spacer(minLength: 6)

            Text(todo.isDone ? "完成" : (todo.isScheduled ? "日程" : "待办"))
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryOnBackground)
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
        // Matches the reference long-press menu exactly.
        .contextMenu {
            Button {
                Task {
                    _ = try? await model.api.updateTodo(
                        id: todo.id,
                        dueAt: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000))
                    onChange()
                }
            } label: {
                Label("设为日程", systemImage: "calendar.badge.plus")
            }

            Button(role: .destructive) {
                Task {
                    try? await model.api.deleteTodo(id: todo.id)
                    onChange()
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            TextField("记一条今天要做的…", text: $draft)
                .font(.system(size: 14))
                .foregroundStyle(theme.onBackground)
                .onSubmit(add)

            Button(action: add) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(canAdd ? theme.accent : theme.secondaryOnBackground))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.onBackground.opacity(0.05)))
    }

    private var canAdd: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    private func add() {
        guard canAdd else { return }
        let title = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        Task {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            _ = try? await model.api.createTodo(
                owner: author, title: title, source: "\(f.string(from: Date())) 添加")
            onChange()
        }
    }
}
