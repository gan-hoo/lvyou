import SwiftUI
import SwiftData

/// 时间线：按时间倒序、按月份分组展示所有打卡记录。
/// （命名为 TravelTimelineView 以避免与 SwiftUI.TimelineView 冲突。）
struct TravelTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CheckIn.visitedAt, order: .reverse) private var checkIns: [CheckIn]
    @State private var pendingDeletion: CheckIn?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if checkIns.isEmpty {
                    ContentUnavailableView {
                        Label("还没有打卡记录", systemImage: "clock")
                    } description: {
                        Text("你的每一次打卡都会按时间顺序记录在这里。")
                    }
                } else {
                    List {
                        ForEach(TimelineSection.make(from: checkIns)) { section in
                            Section(section.title) {
                                ForEach(section.checkIns) { checkIn in
                                    NavigationLink(value: checkIn) {
                                        CheckInRow(checkIn: checkIn)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingDeletion = checkIn
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("时间线")
            .travelDestinations()
            .confirmationDialog(
                "删除这条打卡记录？",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { checkIn in
                Button("删除", role: .destructive) { delete(checkIn) }
            } message: { _ in
                Text("删除后无法恢复。")
            }
            .alert(
                "删除失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func delete(_ checkIn: CheckIn) {
        pendingDeletion = nil
        do {
            try CheckInStore(context: modelContext).delete(checkIn)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    TravelTimelineView()
        .environment(LocationService())
        .modelContainer(PreviewSampleData.container)
}
#endif
