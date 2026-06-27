//
//  ManagerViews.swift
//  test
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AppIntents

private enum ManagerOverallTodoNoteNamespace: String {
    case sectionTask = "manager-overall-section"
    case personalTodo = "manager-overall-personal"
    case managerTodo = "manager-overall-self"
}

private func managerVisibleName(_ member: SectionMember, nicknamesRaw: String) -> String {
    managerDisplayName(for: member, nicknames: decodeManagerCrewNicknames(from: nicknamesRaw))
}

struct ManagerLeadershipTodoItem: Identifiable {
    enum ItemType {
        case sectionTask
        case personalTodo
        case managerTodo
    }

    let id: String
    let sectionName: String
    let title: String
    let dueDate: Date
    let priority: TaskPriority
    let sourceID: UUID
    let sectionID: UUID?
    let memberID: UUID?
    let requiresAcknowledgement: Bool
    let isCompleted: Bool
    let isAwaitingVerification: Bool
    let itemType: ItemType
}

struct ManagerHomeView: View {
    private enum OverallTodoTimelineView: String, CaseIterable, Identifiable {
        case month
        case week
        case day

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month:
                return "Month"
            case .week:
                return "Week"
            case .day:
                return "Day"
            }
        }
    }

    private struct SnapshotMetric: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let systemImage: String
        let tint: Color
    }

    private struct ManagedSnapshotMember: Identifiable {
        let id: String
        var member: SectionMember
        var sectionNames: [String]
        var assignedTaskCount: Int
        var completedTaskCount: Int
        var pendingTaskCount: Int
    }

    let profileName: String
    let walkthroughDestination: DemoDestination
    let walkthroughFocusTarget: WalkthroughTargetID?
    let onSignOut: () -> Void

    @Environment(BluetoothManager.self) private var bluetoothManager
    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("managerAssignedSectionCodesJSON") private var assignedSectionCodesRaw = ""
    @AppStorage("managerPersonalTodosJSON") private var managerPersonalTodosRaw = ""
    @AppStorage("workerPrivateTaskNotesJSON") private var workerPrivateTaskNotesRaw = ""
    @AppStorage("profileAccountID") private var profileAccountID = ""
    @AppStorage("profilePhoneNumber") private var profilePhoneNumber = ""
    @AppStorage("profileEmail") private var profileEmail = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""

    @State private var managerSections: [ManagerSection] = []
    @State private var showCreateSectionSheet = false
    @State private var newSectionName = ""
    @State private var showARCVisor = false
    @State private var emergencyStatusMessage = ""
    @State private var showJoinSectionSheet = false
    @State private var joinSectionCode = ""
    @State private var joinSectionStatusMessage = ""

    @State private var showRenameSectionSheet = false
    @State private var renameSectionName = ""
    @State private var renameSectionID: UUID?
    @State private var expandedManagedSectionIDs: Set<UUID> = []
    @State private var isCrewSnapshotExpanded = true
    @State private var isOverallTodoExpanded = false
    @State private var taskSearchText = ""
    @State private var overallTodoViewMode: OverallTodoTimelineView = .month
    @State private var selectedOverallTodoDate = Date()
    @State private var selectedOverallTodoWeekAnchor = Date()
    @State private var showAddPersonalTodoSheet = false
    @State private var newManagerTodoTitle = ""
    @State private var newManagerTodoDueDate = Date()
    @State private var newManagerTodoPriority: TaskPriority = .medium
    @State private var newManagerTodoNotes = ""
    @State private var showWalkthroughARCVisor = false
    @State private var showWalkthroughAirQuality = false
    @State private var showWalkthroughProfile = false
    @State private var walkthroughSectionID: UUID?

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var managerCrewNicknames: [String: String] {
        decodeManagerCrewNicknames(from: managerCrewNicknamesRaw)
    }

    private var arcVisorPayloadContext: ARCVisorPayloadContext {
        ARCVisorPayloadContext(
            userName: abbreviatedDisplayName(profileName),
            roleTitle: "Crew Lead",
            profileAccountID: profileAccountID,
            profilePhoneNumber: profilePhoneNumber,
            managerSectionsRaw: managerSectionsRaw,
            assignedSectionCodesRaw: assignedSectionCodesRaw,
            managerPersonalTodosRaw: managerPersonalTodosRaw
        )
    }

    private var allSections: [ManagerSection] {
        decodeSections(from: managerSectionsRaw)
    }

    private var assignedSectionCodes: [String] {
        decodeStringArray(from: assignedSectionCodesRaw)
    }

    private var leadershipSections: [ManagerSection] {
        let managedIDs = Set(managerSections.map(\.id))
        return allSections.filter { section in
            assignedSectionCodes.contains(section.codeWord) && !managedIDs.contains(section.id)
        }
    }

    private var leadershipTodoItems: [ManagerLeadershipTodoItem] {
        var items: [ManagerLeadershipTodoItem] = []
        items.append(contentsOf: managerPersonalTodoItems)
        for section in leadershipSections {
            items.append(contentsOf: leadershipTodoItems(for: section))
        }
        return items.sorted { $0.dueDate < $1.dueDate }
    }

    private var filteredLeadershipTodoItems: [ManagerLeadershipTodoItem] {
        let query = taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return leadershipTodoItems }
        let normalizedQuery = query.lowercased()
        return leadershipTodoItems.filter { item in
            item.title.lowercased().contains(normalizedQuery) ||
            item.sectionName.lowercased().contains(normalizedQuery)
        }
    }

    private var managerPersonalTodoItems: [ManagerLeadershipTodoItem] {
        decodeMemberTodos(from: managerPersonalTodosRaw).map { todo in
            ManagerLeadershipTodoItem(
                id: "manager-\(todo.id.uuidString)",
                sectionName: localized("My To-Do", language),
                title: todo.title,
                dueDate: todo.dueDate,
                priority: todo.priority,
                sourceID: todo.id,
                sectionID: nil,
                memberID: nil,
                requiresAcknowledgement: todo.requiresAcknowledgement,
                isCompleted: todo.requiresAcknowledgement ? todo.isCompleted : todo.isMarkedDone,
                isAwaitingVerification: todo.requiresAcknowledgement && todo.isMarkedDone && !todo.isCompleted,
                itemType: .managerTodo
            )
        }
    }

    private var managedSnapshotMembers: [ManagedSnapshotMember] {
        var buckets: [String: ManagedSnapshotMember] = [:]

        for section in allManagedSections {
            for member in section.members {
                let key = managedSnapshotMemberKey(for: member)
                let assignedTasks = assignedTaskCount(for: member, in: section)
                let completedTasks = completedTaskCount(for: member, in: section)
                let pendingTasks = pendingTaskCount(for: member, in: section)

                if var existing = buckets[key] {
                    existing.sectionNames = Array(Set(existing.sectionNames + [section.name])).sorted()
                    existing.assignedTaskCount += assignedTasks
                    existing.completedTaskCount += completedTasks
                    existing.pendingTaskCount += pendingTasks
                    if member.isOnSite {
                        existing.member.isOnSite = true
                    }
                    if existing.member.clockInTime == nil || ((member.clockInTime ?? .distantPast) > (existing.member.clockInTime ?? .distantPast)) {
                        existing.member.clockInTime = member.clockInTime
                    }
                    if existing.member.clockOutTime == nil || ((member.clockOutTime ?? .distantPast) > (existing.member.clockOutTime ?? .distantPast)) {
                        existing.member.clockOutTime = member.clockOutTime
                    }
                    existing.member.todos = mergeTodos(existing.member.todos, member.todos)
                    buckets[key] = existing
                } else {
                    buckets[key] = ManagedSnapshotMember(
                        id: key,
                        member: member,
                        sectionNames: [section.name],
                        assignedTaskCount: assignedTasks,
                        completedTaskCount: completedTasks,
                        pendingTaskCount: pendingTasks
                    )
                }
            }
        }

        return buckets.values.sorted { lhs, rhs in
            managerVisibleName(lhs.member, nicknamesRaw: managerCrewNicknamesRaw) < managerVisibleName(rhs.member, nicknamesRaw: managerCrewNicknamesRaw)
        }
    }

    private var allManagedSections: [ManagerSection] {
        allSections
            .filter { isOwnedSection($0) }
            .sorted { lhs, rhs in
                if lhs.parentSectionID == rhs.parentSectionID {
                    return lhs.name < rhs.name
                }
                return lhs.parentSectionID == nil && rhs.parentSectionID != nil
            }
    }

    private var overviewMetrics: [SnapshotMetric] {
        return [
            SnapshotMetric(title: localized("Members", language), value: "\(managedSnapshotMembers.count)", systemImage: "person.3.fill", tint: .blue),
            SnapshotMetric(title: localized("On Site", language), value: "\(managedSnapshotMembers.filter(\.member.isOnSite).count)", systemImage: "checkmark.seal.fill", tint: .green),
            SnapshotMetric(title: localized("Due Today", language), value: "\(allManagedSections.reduce(0) { $0 + dueTodayCount(in: $1) })", systemImage: "calendar", tint: .orange),
            SnapshotMetric(title: localized("To Verify", language), value: "\(allManagedSections.reduce(0) { $0 + awaitingVerificationCount(in: $1) })", systemImage: "clock.badge.checkmark.fill", tint: .red)
        ]
    }

    private func subsections(for parentID: UUID) -> [ManagerSection] {
        allSections
            .filter { $0.parentSectionID == parentID && isOwnedSection($0) }
            .sorted { $0.name < $1.name }
    }

    private func managedSnapshotMemberKey(for member: SectionMember) -> String {
        if let accountID = member.accountID, !accountID.isEmpty {
            return "account-\(accountID)"
        }

        let normalizedPhone = member.phoneNumber.filter(\.isNumber)
        if !normalizedPhone.isEmpty {
            return "phone-\(normalizedPhone)"
        }

        return "member-\(member.id.uuidString)"
    }

    private func mergeTodos(_ lhs: [MemberTodo], _ rhs: [MemberTodo]) -> [MemberTodo] {
        var merged = lhs
        for todo in rhs where !merged.contains(where: { $0.id == todo.id }) {
            merged.append(todo)
        }
        return merged
    }

    private func dueTodayCount(in section: ManagerSection) -> Int {
        let calendar = Calendar.current
        let sectionTasks = section.sectionTasks.filter { calendar.isDateInToday($0.dueDate) }.count
        let todos = section.members.flatMap(\.todos).filter { calendar.isDateInToday($0.dueDate) }.count
        return sectionTasks + todos
    }

    private func awaitingVerificationCount(in section: ManagerSection) -> Int {
        let tasks = section.sectionTasks.filter { task in
            task.requiresAcknowledgement && task.doneMemberIDs.contains(where: { !task.verifiedMemberIDs.contains($0) })
        }.count
        let todos = section.members.flatMap(\.todos).filter {
            $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
        }.count
        return tasks + todos
    }

    private func assignedTaskCount(for member: SectionMember, in section: ManagerSection) -> Int {
        section.sectionTasks.filter { $0.assigneeIDs.contains(member.id) }.count
    }

    private func completedTaskCount(for member: SectionMember, in section: ManagerSection) -> Int {
        section.sectionTasks.filter {
            $0.requiresAcknowledgement ? $0.verifiedMemberIDs.contains(member.id) : $0.doneMemberIDs.contains(member.id)
        }.count
    }

    private func completedTodoCount(for member: SectionMember) -> Int {
        member.todos.filter { $0.requiresAcknowledgement ? $0.isCompleted : $0.isMarkedDone }.count
    }

    private func pendingTaskCount(for member: SectionMember, in section: ManagerSection) -> Int {
        section.sectionTasks.filter {
            $0.requiresAcknowledgement &&
            $0.assigneeIDs.contains(member.id) &&
            $0.doneMemberIDs.contains(member.id) &&
            !$0.verifiedMemberIDs.contains(member.id)
        }.count
    }

    private func pendingTodoCount(for member: SectionMember) -> Int {
        member.todos.filter {
            $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
        }.count
    }

    private func homeStackedProgressBar(completed: Int, pendingVerification: Int, total: Int) -> some View {
        let remaining = max(total - completed - pendingVerification, 0)
        let safeTotal = max(total, 1)

        return GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: proxy.size.width * CGFloat(completed) / CGFloat(safeTotal))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: proxy.size.width * CGFloat(pendingVerification) / CGFloat(safeTotal))
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: proxy.size.width * CGFloat(remaining) / CGFloat(safeTotal))
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func memberStatusLabel(_ member: SectionMember, in section: ManagerSection) -> String {
        let hasAwaitingTaskVerification = section.sectionTasks.contains { task in
            task.requiresAcknowledgement &&
            task.assigneeIDs.contains(member.id) &&
            task.doneMemberIDs.contains(member.id) &&
            !task.verifiedMemberIDs.contains(member.id)
        }
        let hasAwaitingTodoVerification = member.todos.contains {
            $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
        }

        if hasAwaitingTaskVerification || hasAwaitingTodoVerification {
            return localized("Awaiting Verify", language)
        }
        return member.isOnSite ? localized("On Site", language) : localized("Off Site", language)
    }

    private func memberStatusColor(_ member: SectionMember, in section: ManagerSection) -> Color {
        memberStatusLabel(member, in: section) == localized("Awaiting Verify", language)
            ? .orange
            : (member.isOnSite ? .green : .secondary)
    }

    private func aggregatedMemberStatusLabel(_ item: ManagedSnapshotMember) -> String {
        if item.pendingTaskCount > 0 || pendingTodoCount(for: item.member) > 0 {
            return localized("Awaiting Verify", language)
        }
        return item.member.isOnSite ? localized("On Site", language) : localized("Off Site", language)
    }

    private func aggregatedMemberStatusColor(_ item: ManagedSnapshotMember) -> Color {
        aggregatedMemberStatusLabel(item) == localized("Awaiting Verify", language)
            ? .orange
            : (item.member.isOnSite ? .green : .secondary)
    }

    private func summaryHeatmapCell(completed: Int, total: Int) -> some View {
        let ratio = total == 0 ? 0 : Double(completed) / Double(total)
        let color: Color
        switch ratio {
        case ..<0.34:
            color = .red
        case ..<0.67:
            color = .orange
        default:
            color = .green
        }

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((total == 0 ? Color.secondary : color).opacity(total == 0 ? 0.14 : 0.22))
                .frame(width: 40, height: 30)
            Text(total == 0 ? "0" : "\(completed)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(total == 0 ? .secondary : color)
        }
    }

    private var heatmapLegend: some View {
        HStack(spacing: 10) {
            heatmapLegendItem(color: .red, label: localized("Low", language))
            heatmapLegendItem(color: .orange, label: localized("Partial", language))
            heatmapLegendItem(color: .green, label: localized("Strong", language))
            heatmapLegendItem(color: .secondary, label: localized("No items", language), usesMutedStyle: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func heatmapLegendItem(color: Color, label: String, usesMutedStyle: Bool = false) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color.opacity(usesMutedStyle ? 0.2 : 0.8))
                .frame(width: 10, height: 10)
            Text(label)
        }
    }

    private func leadershipTodoItems(for section: ManagerSection) -> [ManagerLeadershipTodoItem] {
        guard let member = leadershipMember(in: section) else { return [] }

        let sectionTasks = section.sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .map { task in
                ManagerLeadershipTodoItem(
                    id: "section-\(task.id.uuidString)",
                    sectionName: section.name,
                    title: task.title,
                    dueDate: task.dueDate,
                    priority: task.priority,
                    sourceID: task.id,
                    sectionID: section.id,
                    memberID: member.id,
                    requiresAcknowledgement: task.requiresAcknowledgement,
                    isCompleted: task.requiresAcknowledgement ? task.verifiedMemberIDs.contains(member.id) : task.doneMemberIDs.contains(member.id),
                    isAwaitingVerification: task.requiresAcknowledgement && task.doneMemberIDs.contains(member.id) && !task.verifiedMemberIDs.contains(member.id),
                    itemType: .sectionTask
                )
            }

        let personalTodos = member.todos.map { todo in
                ManagerLeadershipTodoItem(
                    id: "personal-\(todo.id.uuidString)",
                    sectionName: section.name,
                    title: todo.title,
                    dueDate: todo.dueDate,
                    priority: todo.priority,
                    sourceID: todo.id,
                    sectionID: section.id,
                    memberID: member.id,
                    requiresAcknowledgement: todo.requiresAcknowledgement,
                    isCompleted: todo.requiresAcknowledgement ? todo.isCompleted : todo.isMarkedDone,
                    isAwaitingVerification: todo.requiresAcknowledgement && todo.isMarkedDone && !todo.isCompleted,
                    itemType: .personalTodo
                )
            }

        return sectionTasks + personalTodos
    }

    private func leadershipMember(in section: ManagerSection) -> SectionMember? {
        section.members.first(where: { member in
            (!profileAccountID.isEmpty && member.accountID == profileAccountID) || member.phoneNumber == profilePhoneNumber
        })
    }

    private func todoTag(for item: ManagerLeadershipTodoItem) -> String {
        switch item.itemType {
        case .sectionTask:
            return localized("Crew Task", language)
        case .personalTodo:
            return localized("Personal To-Do", language)
        case .managerTodo:
            return localized("My To-Do", language)
        }
    }

    init(
        profileName: String,
        walkthroughDestination: DemoDestination = .home,
        walkthroughFocusTarget: WalkthroughTargetID? = nil,
        onSignOut: @escaping () -> Void
    ) {
        self.profileName = profileName
        self.walkthroughDestination = walkthroughDestination
        self.walkthroughFocusTarget = walkthroughFocusTarget
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { scrollProxy in
                List {
                    managerHeaderSection
                    managerEmergencySection
                    managerARCVisorSection
                    managerCrewSnapshotSection
                    managerOverallTodoSection
                    managerManagedSectionsSection
                    managerLeadershipSectionsSection
                    managerProfileSection
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Sign Out") {
                            onSignOut()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            resetManagerTodoComposer()
                            showAddPersonalTodoSheet = true
                        } label: {
                            Image(systemName: "checklist.checked")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCreateSectionSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    scrollToWalkthroughTarget(using: scrollProxy)
                }
                .onChange(of: walkthroughFocusTarget) {
                    scrollToWalkthroughTarget(using: scrollProxy)
                    applyWalkthroughDestination(walkthroughDestination)
                }
                .background(walkthroughNavigationLinks)
            }
            .sheet(isPresented: $showCreateSectionSheet) {
                NavigationView {
                    Form {
                        Section("New Section") {
                            TextField("Crew name", text: $newSectionName)
                                .textInputAutocapitalization(.words)
                        }

                        Section {
                            Button("Create Section") {
                                createSection()
                            }
                            .disabled(newSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .navigationTitle("Create Section")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showCreateSectionSheet = false
                                newSectionName = ""
                            }
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $showRenameSectionSheet) {
                NavigationView {
                    Form {
                        Section("Rename Section") {
                            TextField("Crew name", text: $renameSectionName)
                                .textInputAutocapitalization(.words)
                        }

                        Section {
                            Button("Save") {
                                renameSection()
                            }
                            .disabled(renameSectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .navigationTitle("Rename Section")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showRenameSectionSheet = false
                                renameSectionName = ""
                                renameSectionID = nil
                            }
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $showJoinSectionSheet) {
                NavigationView {
                    Form {
                        Section(localized("Join Section", language)) {
                            TextField(localized("Crew code word", language), text: $joinSectionCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            Text(localized("Enter the section code word from leadership to join their section dashboard.", language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !joinSectionStatusMessage.isEmpty {
                                Text(joinSectionStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section {
                            Button(localized("Join Section", language)) {
                                joinLeadershipSection()
                            }
                            .disabled(joinSectionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .navigationTitle(localized("Join Section", language))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(localized("Cancel", language)) {
                                showJoinSectionSheet = false
                                joinSectionCode = ""
                                joinSectionStatusMessage = ""
                            }
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }
            .sheet(isPresented: $showAddPersonalTodoSheet) {
                NavigationView {
                    Form {
                        Section(localized("My To-Do", language)) {
                            TextField(localized("To-do item", language), text: $newManagerTodoTitle)
                                .textInputAutocapitalization(.sentences)

                            Picker(localized("Priority", language), selection: $newManagerTodoPriority) {
                                ForEach(TaskPriority.allCases) { priority in
                                    Text(priority.title).tag(priority)
                                }
                            }

                            DatePicker(
                                localized("Due Date", language),
                                selection: $newManagerTodoDueDate,
                                displayedComponents: .date
                            )

                            TextEditor(text: $newManagerTodoNotes)
                                .frame(minHeight: 90)
                                .overlay(alignment: .topLeading) {
                                    if newManagerTodoNotes.isEmpty {
                                        Text(localized("Crew Lead notes (optional)", language))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 8)
                                            .padding(.leading, 6)
                                    }
                                }
                        }

                        Section {
                            Button(localized("Add To-Do", language)) {
                                addManagerPersonalTodo()
                            }
                            .disabled(newManagerTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .navigationTitle(localized("Add To-Do", language))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(localized("Cancel", language)) {
                                showAddPersonalTodoSheet = false
                                resetManagerTodoComposer()
                            }
                        }
                    }
                }
                .navigationViewStyle(.stack)
            }

            Text("Select a section")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
        }
        .sheet(isPresented: $showARCVisor) {
            NavigationView {
                ARCVisorHubView(payloadContext: arcVisorPayloadContext)
                    .environment(bluetoothManager)
            }
            .navigationViewStyle(.stack)
        }
        .onAppear {
            seedDemoSectionIfNeeded()
            seedDemoLeadershipAssignmentIfNeeded()
            managerSections = ownedSectionsFromStorage()
            applyWalkthroughDestination(walkthroughDestination)
        }
        .onChange(of: walkthroughDestination) {
            applyWalkthroughDestination(walkthroughDestination)
        }
        .onChange(of: managerSectionsRaw) { newValue in
            managerSections = ownedSections(from: newValue)
        }
    }

    @ViewBuilder
    private var walkthroughNavigationLinks: some View {
        NavigationLink(
            isActive: $showWalkthroughARCVisor,
            destination: {
                ARCVisorHubView(payloadContext: arcVisorPayloadContext)
                    .environment(bluetoothManager)
            },
            label: { EmptyView() }
        )
        .hidden()

        NavigationLink(
            isActive: $showWalkthroughAirQuality,
            destination: {
                AirQualityMonitorView()
            },
            label: { EmptyView() }
        )
        .hidden()

        NavigationLink(
            isActive: $showWalkthroughProfile,
            destination: {
                ManagerProfileDetailView(
                    profileName: profileName,
                    profileAccountID: profileAccountID,
                    profilePhoneNumber: profilePhoneNumber,
                    profileEmail: profileEmail,
                    walkthroughFocusTarget: walkthroughFocusTarget
                )
            },
            label: { EmptyView() }
        )
        .hidden()

        NavigationLink(
            isActive: Binding(
                get: { walkthroughSectionID != nil },
                set: { isActive in
                    if !isActive {
                        walkthroughSectionID = nil
                    }
                }
            ),
            destination: {
                if let walkthroughSectionID {
                    ManagedSectionHostView(
                        sectionID: walkthroughSectionID,
                        walkthroughDestination: walkthroughDestination,
                        walkthroughFocusTarget: walkthroughFocusTarget
                    )
                }
            },
            label: { EmptyView() }
        )
        .hidden()
    }

    private var managerHeaderSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("ARCLink")
                    .font(.title2.weight(.semibold))
                Text(greetingText(name: profileName.isEmpty ? localized("Crew Lead", language) : abbreviatedDisplayName(profileName), language: language))
                    .font(.largeTitle.weight(.bold))
            }
            .padding(.vertical, 4)
        }
    }

    private var managerARCVisorSection: some View {
        Section {
            Button {
                showARCVisor = true
            } label: {
                Label(localized("Open ARCVisor", language), systemImage: "visionpro")
                    .foregroundStyle(Color.arcAccentOrange)
            }
            .buttonStyle(.plain)
            .id(WalkthroughTargetID.arcVisorButton.rawValue)
            .walkthroughTarget(.arcVisorButton)

            NavigationLink {
                AirQualityMonitorView()
            } label: {
                Label(localized("Air Quality Data", language), systemImage: "aqi.medium")
            }
            .id(WalkthroughTargetID.airQualityButton.rawValue)
            .walkthroughTarget(.airQualityButton)
        }
    }

    private var managerEmergencySection: some View {
        Section {
            Button {
                sendEmergencyEvacuate()
            } label: {
                Label("Emergency Evacuate", systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!bluetoothManager.isConnected())

            if !emergencyStatusMessage.isEmpty {
                Text(emergencyStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id(WalkthroughTargetID.managerEmergency.rawValue)
        .walkthroughTarget(.managerEmergency)
    }

    @ViewBuilder
    private var managerCrewSnapshotSection: some View {
        if !managedSnapshotMembers.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $isCrewSnapshotExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(localized("All Managed Members", language))
                                .font(.headline)
                            Spacer()
                            Text("\(allManagedSections.count) \(localized("crews", language).lowercased())")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(overviewMetrics) { metric in
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(metric.title, systemImage: metric.systemImage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(metric.tint)
                                    Text(metric.value)
                                        .font(.title3.weight(.bold))
                                    Rectangle()
                                        .fill(metric.tint.opacity(0.18))
                                        .frame(height: 5)
                                        .clipShape(Capsule())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Member Status Board", language))
                                .font(.subheadline.weight(.semibold))

                            ForEach(managedSnapshotMembers.prefix(6)) { item in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(aggregatedMemberStatusColor(item))
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(managerVisibleName(item.member, nicknamesRaw: managerCrewNicknamesRaw))
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(item.sectionNames.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(aggregatedMemberStatusLabel(item))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(aggregatedMemberStatusColor(item).opacity(0.15), in: Capsule())
                                        .foregroundStyle(aggregatedMemberStatusColor(item))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Completion Overview", language))
                                .font(.subheadline.weight(.semibold))

                            ForEach(managedSnapshotMembers.prefix(6)) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(managerVisibleName(item.member, nicknamesRaw: managerCrewNicknamesRaw))
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(1)
                                            Text(item.sectionNames.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(item.completedTaskCount + completedTodoCount(for: item.member))/\(item.assignedTaskCount + item.member.todos.count)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    homeStackedProgressBar(
                                        completed: item.completedTaskCount + completedTodoCount(for: item.member),
                                        pendingVerification: item.pendingTaskCount + pendingTodoCount(for: item.member),
                                        total: item.assignedTaskCount + item.member.todos.count
                                    )
                                    HStack {
                                        Text("\(localized("Tasks", language)): \(item.completedTaskCount)/\(item.assignedTaskCount)")
                                        Spacer()
                                        Text("\(localized("To-Dos", language)): \(completedTodoCount(for: item.member))/\(item.member.todos.count)")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(localized("Crew Snapshot", language))
                }
            }
            .id(WalkthroughTargetID.crewSnapshot.rawValue)
            .walkthroughTarget(.crewSnapshot)
        }
    }

    private var managerOverallTodoSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isOverallTodoExpanded) {
                TextField(localized("Search tasks", language), text: $taskSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if filteredLeadershipTodoItems.isEmpty {
                    Text(taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localized("No leadership to-dos assigned yet.", language) : localized("No matching tasks.", language))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(localized("Task View", language), selection: $overallTodoViewMode) {
                        ForEach(OverallTodoTimelineView.allCases) { mode in
                            Text(localized(mode.title, language)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch overallTodoViewMode {
                    case .month:
                        EventCalendarView(
                            selectedDate: $selectedOverallTodoDate,
                            highlightedDates: filteredLeadershipTodoItems.map(\.dueDate),
                            language: language
                        )

                        let dailyItems = overallTodoItems(on: selectedOverallTodoDate)
                        if dailyItems.isEmpty {
                            Text(localized("No to-dos on this date.", language))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dailyItems) { item in
                                overallTodoNavigationRow(item)
                            }
                        }
                    case .week:
                        DatePicker(
                            localized("Week Of", language),
                            selection: $selectedOverallTodoWeekAnchor,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)

                        let weeklyBuckets = overallTodoItemsForSelectedWeek()
                        if weeklyBuckets.isEmpty {
                            Text(localized("No to-dos in this week.", language))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(weeklyBuckets, id: \.date) { bucket in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(overallWeekHeaderString(for: bucket.date))
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(bucket.items) { item in
                                        overallTodoNavigationRow(item)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    case .day:
                        DatePicker(
                            localized("Day", language),
                            selection: $selectedOverallTodoDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)

                        let dailyItems = overallTodoItems(on: selectedOverallTodoDate)
                        if dailyItems.isEmpty {
                            Text(localized("No to-dos on this day.", language))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(dailyItems) { item in
                                overallTodoNavigationRow(item)
                            }
                        }
                    }
                }
            } label: {
                Text(localized("Overall To-Do List", language))
                    .id(WalkthroughTargetID.overallTodos.rawValue)
                    .walkthroughTarget(.overallTodos)
            }
        }
    }

    private var managerManagedSectionsSection: some View {
        Section(localized("Managed Crews", language)) {
            if managerSections.isEmpty {
                Text(localized("No managed crews yet. Tap + to create one.", language))
                    .foregroundStyle(.secondary)
            } else {
                ForEach($managerSections) { $section in
                    managedSectionRow(
                        $section,
                        isPrimaryWalkthroughSection: section.id == managerSections.first?.id
                    )
                }
            }
        }
    }

    private var managerLeadershipSectionsSection: some View {
        Section {
            if leadershipSections.isEmpty {
                Text(localized("No leadership crews joined yet.", language))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(leadershipSections) { section in
                    NavigationLink {
                        ManagerAssignedSectionDashboardView(
                            profileName: profileName,
                            profileAccountID: profileAccountID,
                            profilePhoneNumber: profilePhoneNumber,
                            sectionCode: section.codeWord
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(section.name)
                                    .font(.headline)
                                Spacer()
                                Label(section.codeWord, systemImage: "link.badge.plus")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(section.members.count) crews • \(section.groupChats.count) group chats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } header: {
            HStack {
                Text(localized("Leadership Crews", language))
                Spacer()
                Button {
                    joinSectionStatusMessage = ""
                    joinSectionCode = ""
                    showJoinSectionSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .id(WalkthroughTargetID.leadershipSections.rawValue)
        .walkthroughTarget(.leadershipSections)
    }

    private var managerProfileSection: some View {
        Section {
            NavigationLink {
                ManagerProfileDetailView(
                    profileName: profileName,
                    profileAccountID: profileAccountID,
                    profilePhoneNumber: profilePhoneNumber,
                    profileEmail: profileEmail
                )
            } label: {
                Label(localized("My Profile", language), systemImage: "person.crop.circle")
            }
        }
        .id(WalkthroughTargetID.profile.rawValue)
        .walkthroughTarget(.profile)
    }

    @ViewBuilder
    private func managedSectionRow(_ section: Binding<ManagerSection>, isPrimaryWalkthroughSection: Bool) -> some View {
        let childSections = subsections(for: section.wrappedValue.id)
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedManagedSectionIDs.contains(section.wrappedValue.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedManagedSectionIDs.insert(section.wrappedValue.id)
                    } else {
                        expandedManagedSectionIDs.remove(section.wrappedValue.id)
                    }
                }
            )
        ) {
            if childSections.isEmpty {
                Text(localized("No sub-crews yet.", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(childSections) { subsection in
                    NavigationLink {
                        ManagedSectionHostView(sectionID: subsection.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(subsection.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Label(subsection.codeWord, systemImage: "link")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(subsection.members.count) crews • \(subsection.groupChats.count) group chats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } label: {
            NavigationLink {
                ManagedSectionHostView(sectionID: section.wrappedValue.id)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(section.wrappedValue.name)
                            .font(.headline)
                        Spacer()
                        Label(section.wrappedValue.codeWord, systemImage: "key.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .id(
                                isPrimaryWalkthroughSection
                                ? WalkthroughTargetID.managedSectionCode.rawValue
                                : "managed-section-code-\(section.wrappedValue.id.uuidString)"
                            )
                            .walkthroughTarget(isPrimaryWalkthroughSection ? .managedSectionCode : nil)
                    }
                    Text("\(section.wrappedValue.members.count) crews • \(section.wrappedValue.groupChats.count) group chats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .id(
                            isPrimaryWalkthroughSection
                            ? WalkthroughTargetID.managedSectionSummary.rawValue
                            : "managed-section-summary-\(section.wrappedValue.id.uuidString)"
                        )
                        .walkthroughTarget(isPrimaryWalkthroughSection ? .managedSectionSummary : nil)
                }
                .padding(.vertical, 2)
                .id(
                    isPrimaryWalkthroughSection
                    ? WalkthroughTargetID.managedSectionCard.rawValue
                    : "managed-section-\(section.wrappedValue.id.uuidString)"
                )
                .walkthroughTarget(isPrimaryWalkthroughSection ? .managedSectionCard : nil)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Rename") {
                renameSectionID = section.wrappedValue.id
                renameSectionName = section.wrappedValue.name
                showRenameSectionSheet = true
            }
            .tint(Color.arcAccentOrange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
                deleteSection(id: section.wrappedValue.id)
            }
        }
    }

    private func scrollToWalkthroughTarget(using scrollProxy: ScrollViewProxy) {
        guard let walkthroughFocusTarget else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(walkthroughFocusTarget.rawValue, anchor: walkthroughScrollAnchor(for: walkthroughFocusTarget))
            }
        }
    }

    private func walkthroughScrollAnchor(for target: WalkthroughTargetID) -> UnitPoint {
        switch target {
        case .overallTodos, .managedSectionCard:
            return .top
        default:
            return .center
        }
    }

    private func applyWalkthroughDestination(_ destination: DemoDestination) {
        if walkthroughFocusTarget == .overallTodos {
            isOverallTodoExpanded = true
        } else if walkthroughFocusTarget != nil {
            isOverallTodoExpanded = false
        }

        if walkthroughFocusTarget == .crewSnapshot {
            isCrewSnapshotExpanded = true
        } else if walkthroughFocusTarget != nil {
            isCrewSnapshotExpanded = false
        }

        switch destination {
        case .home:
            showARCVisor = false
            showWalkthroughARCVisor = false
            showWalkthroughAirQuality = false
            showWalkthroughProfile = false
            walkthroughSectionID = nil
        case .arcVisor:
            showARCVisor = false
            showWalkthroughARCVisor = true
            showWalkthroughAirQuality = false
            showWalkthroughProfile = false
            walkthroughSectionID = nil
        case .airQuality:
            showARCVisor = false
            showWalkthroughARCVisor = false
            showWalkthroughProfile = false
            walkthroughSectionID = nil
            showWalkthroughAirQuality = true
        case .profile:
            showARCVisor = false
            showWalkthroughARCVisor = false
            showWalkthroughAirQuality = false
            walkthroughSectionID = nil
            showWalkthroughProfile = true
        case .sectionDetail(let sectionID),
             .sectionTasks(let sectionID),
             .sectionMembers(let sectionID),
             .sectionChats(let sectionID),
             .sectionTimeClock(let sectionID),
             .sectionSettings(let sectionID):
            showARCVisor = false
            showWalkthroughARCVisor = false
            showWalkthroughAirQuality = false
            showWalkthroughProfile = false
            walkthroughSectionID = sectionID
        }
    }

    private func createSection() {
        let cleanedName = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        let codeWord = randomSiteCodeWord(existingCodes: Set(managerSections.map(\.codeWord)))
        managerSections.insert(
            ManagerSection(
                ownerAccountID: profileAccountID,
                name: cleanedName,
                codeWord: codeWord
            ),
            at: 0
        )
        saveSections()

        newSectionName = ""
        showCreateSectionSheet = false
    }

    private func renameSection() {
        let cleanedName = renameSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, let renameSectionID else { return }
        guard let index = managerSections.firstIndex(where: { $0.id == renameSectionID }) else { return }

        managerSections[index].name = cleanedName
        saveSections()

        showRenameSectionSheet = false
        renameSectionName = ""
        self.renameSectionID = nil
    }

    private func deleteSection(id: UUID) {
        let allStoredSections = decodeSections(from: managerSectionsRaw)
        let idsToDelete = descendantSectionIDs(for: id, in: allStoredSections).union([id])
        managerSections.removeAll(where: { idsToDelete.contains($0.id) })
        managerSectionsRaw = encodeSections(allStoredSections.filter { !idsToDelete.contains($0.id) })
        saveSections()
    }

    private func saveSections() {
        let allStoredSections = decodeSections(from: managerSectionsRaw)
        let managedIDs = Set(managerSections.map(\.id))
        let remainingSections = allStoredSections.filter { !managedIDs.contains($0.id) }
        managerSectionsRaw = encodeSections(managerSections + remainingSections)
    }

    private func sendEmergencyEvacuate() {
        guard bluetoothManager.isConnected() else {
            emergencyStatusMessage = "Bluetooth not connected."
            return
        }

        do {
            let payload: [String: String] = [
                "type": "emergency",
                "priority": "critical",
                "title": "Emergency Evacuate",
                "message": "Emergency evacuate. Leave the area and follow site evacuation procedures."
            ]

            let data = try JSONSerialization.data(withJSONObject: payload)
            let json = String(data: data, encoding: .utf8) ?? ""

            try bluetoothManager.writeString(json)

            appendEmergencyAlertToManagedSections()

            emergencyStatusMessage = "Emergency evacuate sent."

        } catch {
            emergencyStatusMessage = "Failed to send emergency evacuate."
        }
    }

    private func appendEmergencyAlertToManagedSections() {
        var sections = decodeSections(from: managerSectionsRaw)
        let managedIDs = Set(allManagedSections.map(\.id))
        for index in sections.indices where managedIDs.contains(sections[index].id) {
            sections[index].alerts.insert(
                SectionAlert(
                    title: "Emergency Evacuate",
                    message: "Emergency evacuate. Leave the area and follow site evacuation procedures."
                ),
                at: 0
            )
        }
        managerSectionsRaw = encodeSections(sections)
        managerSections = ownedSections(from: managerSectionsRaw)
    }

    private func seedDemoSectionIfNeeded() {
        managerSectionsRaw = encodeSections(mergedSectionsWithDemoSection(from: managerSectionsRaw))
    }

    private func seedDemoLeadershipAssignmentIfNeeded() {
        let defaultAssignedCodes = defaultLeadershipAssignedSectionCodes(for: profileAccountID)
        guard !defaultAssignedCodes.isEmpty else { return }

        var assignedCodes = assignedSectionCodes
        for code in defaultAssignedCodes where !assignedCodes.contains(code) {
            assignedCodes.append(code)
        }
        assignedSectionCodesRaw = encodeStringArray(assignedCodes)
    }

    private func ownedSectionsFromStorage() -> [ManagerSection] {
        ownedSections(from: managerSectionsRaw)
    }

    private func ownedSections(from rawValue: String) -> [ManagerSection] {
        decodeSections(from: rawValue).filter { isOwnedSection($0) && $0.parentSectionID == nil }
    }

    private func isOwnedSection(_ section: ManagerSection) -> Bool {
        if let ownerAccountID = section.ownerAccountID {
            return ownerAccountID == profileAccountID
        }
        return profileAccountID == defaultManagerDemoProfile().accountID
    }

    private func joinLeadershipSection() {
        let normalizedCode = normalizeCodeWord(joinSectionCode)
        guard let matchedSection = allSections.first(where: { $0.codeWord == normalizedCode }) else {
            joinSectionStatusMessage = localized("No section found for that code word.", language)
            return
        }
        guard matchedSection.ownerAccountID != profileAccountID else {
            joinSectionStatusMessage = localized("You already manage this section.", language)
            return
        }
        guard !assignedSectionCodes.contains(normalizedCode) else {
            joinSectionStatusMessage = localized("You're already in this leadership section.", language)
            return
        }

        var updatedSections = allSections
        guard let sectionIndex = updatedSections.firstIndex(where: { $0.id == matchedSection.id }) else { return }

        if let memberIndex = updatedSections[sectionIndex].members.firstIndex(where: {
            (!profileAccountID.isEmpty && $0.accountID == profileAccountID) || $0.phoneNumber == profilePhoneNumber
        }) {
            updatedSections[sectionIndex].members[memberIndex].name = profileName.isEmpty ? localized("Crew Lead", language) : profileName
            updatedSections[sectionIndex].members[memberIndex].phoneNumber = profilePhoneNumber
            updatedSections[sectionIndex].members[memberIndex].accountID = profileAccountID.isEmpty ? nil : profileAccountID
            updatedSections[sectionIndex].members[memberIndex].role = .foreman
        } else {
            updatedSections[sectionIndex].members.append(
                SectionMember(
                    accountID: profileAccountID.isEmpty ? nil : profileAccountID,
                    name: profileName.isEmpty ? localized("Crew Lead", language) : profileName,
                    phoneNumber: profilePhoneNumber,
                    role: .foreman,
                    isOnSite: false
                )
            )
        }

        managerSectionsRaw = encodeSections(updatedSections)
        assignedSectionCodesRaw = encodeStringArray(assignedSectionCodes + [normalizedCode])
        joinSectionStatusMessage = localized("Joined leadership section.", language)
        showJoinSectionSheet = false
        joinSectionCode = ""
    }

    private func descendantSectionIDs(for id: UUID, in sections: [ManagerSection]) -> Set<UUID> {
        let directChildren = sections.filter { $0.parentSectionID == id }.map(\.id)
        return directChildren.reduce(into: Set<UUID>()) { result, childID in
            result.insert(childID)
            result.formUnion(descendantSectionIDs(for: childID, in: sections))
        }
    }

    private func addManagerPersonalTodo() {
        let cleanedTitle = newManagerTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        var todos = decodeMemberTodos(from: managerPersonalTodosRaw)
        todos.append(
            MemberTodo(
                title: cleanedTitle,
                dueDate: newManagerTodoDueDate,
                priority: newManagerTodoPriority,
                managerNotes: newManagerTodoNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        managerPersonalTodosRaw = encodeMemberTodos(todos)
        showAddPersonalTodoSheet = false
        resetManagerTodoComposer()
    }

    private func toggleOverallTodoCompletion(_ item: ManagerLeadershipTodoItem) {
        switch item.itemType {
        case .managerTodo:
            var todos = decodeMemberTodos(from: managerPersonalTodosRaw)
            guard let index = todos.firstIndex(where: { $0.id == item.sourceID }) else { return }
            let newValue = !item.isCompleted
            todos[index].isMarkedDone = newValue
            todos[index].isCompleted = newValue
            managerPersonalTodosRaw = encodeMemberTodos(todos)

        case .personalTodo:
            guard let sectionID = item.sectionID, let memberID = item.memberID else { return }
            var sections = decodeSections(from: managerSectionsRaw)
            guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
                  let memberIndex = sections[sectionIndex].members.firstIndex(where: { $0.id == memberID }),
                  let todoIndex = sections[sectionIndex].members[memberIndex].todos.firstIndex(where: { $0.id == item.sourceID }) else { return }

            let newValue = !item.isCompleted
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isMarkedDone = newValue
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted = newValue
            managerSectionsRaw = encodeSections(sections)

        case .sectionTask:
            guard let sectionID = item.sectionID, let memberID = item.memberID else { return }
            var sections = decodeSections(from: managerSectionsRaw)
            guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
                  let taskIndex = sections[sectionIndex].sectionTasks.firstIndex(where: { $0.id == item.sourceID }) else { return }

            let newValue = !item.isCompleted
            if newValue {
                if !sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.contains(memberID) {
                    sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.append(memberID)
                }
                if !sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.contains(memberID) {
                    sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.append(memberID)
                }
            } else {
                sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.removeAll(where: { $0 == memberID })
                sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.removeAll(where: { $0 == memberID })
            }
            managerSectionsRaw = encodeSections(sections)
        }
    }

    private func overallTodoStatusImage(for item: ManagerLeadershipTodoItem) -> String {
        if item.isAwaitingVerification {
            return "clock.badge.checkmark.fill"
        }
        return item.isCompleted ? "checkmark.circle.fill" : "circle"
    }

    private func overallTodoStatusColor(for item: ManagerLeadershipTodoItem) -> Color {
        if item.isAwaitingVerification {
            return .orange
        }
        return item.isCompleted ? .green : .secondary
    }

    @ViewBuilder
    private func overallTodoNavigationRow(_ item: ManagerLeadershipTodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggleOverallTodoCompletion(item)
            } label: {
                Image(systemName: overallTodoStatusImage(for: item))
                    .font(.title3)
                    .foregroundStyle(overallTodoStatusColor(for: item))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            switch item.itemType {
            case .sectionTask:
                if let task = overallSectionTask(for: item) {
                    NavigationLink {
                        WorkerTaskDetailView(
                            task: task,
                            isCompleted: item.requiresAcknowledgement ? task.doneMemberIDs.contains(item.memberID ?? UUID()) : item.isCompleted,
                            isVerified: item.isCompleted,
                            privateNote: overallPrivateNote(for: item),
                            onToggleCompleted: { isDone in
                                toggleOverallTodoCompletion(to: isDone, item: item)
                            },
                            onSavePrivateNote: { note in
                                setOverallPrivateNote(note, for: item)
                            }
                        )
                    } label: {
                        overallTodoRowContent(item)
                    }
                } else {
                    overallTodoRowContent(item)
                }
            case .personalTodo, .managerTodo:
                if let todo = overallMemberTodo(for: item) {
                    NavigationLink {
                        WorkerPersonalTodoDetailView(
                            todo: todo,
                            privateNote: overallPrivateNote(for: item),
                            onToggleCompleted: { isDone in
                                toggleOverallTodoCompletion(to: isDone, item: item)
                            },
                            onSavePrivateNote: { note in
                                setOverallPrivateNote(note, for: item)
                            }
                        )
                    } label: {
                        overallTodoRowContent(item)
                    }
                } else {
                    overallTodoRowContent(item)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func overallTodoRowContent(_ item: ManagerLeadershipTodoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Text(item.priority.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.priority.color.opacity(0.18), in: Capsule())
            }

            Text("\(localized("From", language)): \(item.sectionName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("\(localized("Due", language)) \(item.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(todoTag(for: item))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func overallTodoItems(on date: Date) -> [ManagerLeadershipTodoItem] {
        filteredLeadershipTodoItems
            .filter { Calendar.current.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func overallTodoItemsForSelectedWeek() -> [(date: Date, items: [ManagerLeadershipTodoItem])] {
        let start = startOfWeek(for: selectedOverallTodoWeekAnchor)
        return (0..<7).compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dayItems = overallTodoItems(on: day)
            return dayItems.isEmpty ? nil : (day, dayItems)
        }
    }

    private func overallWeekHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func overallSectionTask(for item: ManagerLeadershipTodoItem) -> SectionTask? {
        guard let sectionID = item.sectionID else { return nil }
        return decodeSections(from: managerSectionsRaw)
            .first(where: { $0.id == sectionID })?
            .sectionTasks.first(where: { $0.id == item.sourceID })
    }

    private func overallMemberTodo(for item: ManagerLeadershipTodoItem) -> MemberTodo? {
        switch item.itemType {
        case .managerTodo:
            return decodeMemberTodos(from: managerPersonalTodosRaw).first(where: { $0.id == item.sourceID })
        case .personalTodo:
            guard let sectionID = item.sectionID, let memberID = item.memberID else { return nil }
            return decodeSections(from: managerSectionsRaw)
                .first(where: { $0.id == sectionID })?
                .members.first(where: { $0.id == memberID })?
                .todos.first(where: { $0.id == item.sourceID })
        case .sectionTask:
            return nil
        }
    }

    private func toggleOverallTodoCompletion(to newValue: Bool, item: ManagerLeadershipTodoItem) {
        if item.isCompleted == newValue {
            return
        }
        toggleOverallTodoCompletion(item)
    }

    private func overallPrivateNote(for item: ManagerLeadershipTodoItem) -> String {
        decodeWorkerPrivateNotes(workerPrivateTaskNotesRaw)[overallPrivateNoteKey(for: item)] ?? ""
    }

    private func setOverallPrivateNote(_ note: String, for item: ManagerLeadershipTodoItem) {
        var notes = decodeWorkerPrivateNotes(workerPrivateTaskNotesRaw)
        notes[overallPrivateNoteKey(for: item)] = note
        workerPrivateTaskNotesRaw = encodeWorkerPrivateNotes(notes)
    }

    private func overallPrivateNoteKey(for item: ManagerLeadershipTodoItem) -> String {
        let namespace: ManagerOverallTodoNoteNamespace
        switch item.itemType {
        case .sectionTask:
            namespace = .sectionTask
        case .personalTodo:
            namespace = .personalTodo
        case .managerTodo:
            namespace = .managerTodo
        }
        return "\(namespace.rawValue)|\(profilePhoneNumber)|\(item.sourceID.uuidString)"
    }

    private func resetManagerTodoComposer() {
        newManagerTodoTitle = ""
        newManagerTodoDueDate = Date()
        newManagerTodoPriority = .medium
        newManagerTodoNotes = ""
    }
}

struct ManagerProfileDetailView: View {
    let profileName: String
    let profileAccountID: String
    let profilePhoneNumber: String
    let profileEmail: String
    let walkthroughFocusTarget: WalkthroughTargetID?

    init(
        profileName: String,
        profileAccountID: String,
        profilePhoneNumber: String,
        profileEmail: String,
        walkthroughFocusTarget: WalkthroughTargetID? = nil
    ) {
        self.profileName = profileName
        self.profileAccountID = profileAccountID
        self.profilePhoneNumber = profilePhoneNumber
        self.profileEmail = profileEmail
        self.walkthroughFocusTarget = walkthroughFocusTarget
    }

    @AppStorage("profileAccountID") private var savedProfileAccountID = ""
    @AppStorage("profilePhoneNumber") private var savedProfilePhoneNumber = ""
    @AppStorage("profileEmail") private var savedProfileEmail = ""
    @AppStorage("profilePassword") private var savedProfilePassword = ""
    @AppStorage("profileLanguage") private var savedProfileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("registeredProfilesJSON") private var registeredProfilesRaw = ""

    @State private var emailDraft = ""
    @State private var selectedLanguage: AppLanguage = .english
    @State private var currentPasswordDraft = ""
    @State private var newPasswordDraft = ""
    @State private var confirmPasswordDraft = ""
    @State private var emailStatusMessage = ""
    @State private var passwordStatusMessage = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: savedProfileLanguageRawValue) ?? .english
    }

    var body: some View {
        List {
            Section(localized("Profile", language)) {
                Text(profileName.isEmpty ? "Crew Lead" : profileName)
                Text(localized("Role: Crew Lead", language))
                    .foregroundStyle(.secondary)
                if !profileAccountID.isEmpty {
                    Text(localized("Account ID", language) + ": \(profileAccountID)")
                        .foregroundStyle(.secondary)
                }
                if !profilePhoneNumber.isEmpty {
                    Text(localized("Phone", language) + ": \(profilePhoneNumber)")
                        .foregroundStyle(.secondary)
                }
                if !savedProfileEmail.isEmpty {
                    Text(localized("Email", language) + ": \(savedProfileEmail)")
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Email", language)) {
                TextField(localized("Email address", language), text: $emailDraft)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(localized("Save Email", language)) {
                    saveEmail()
                }
                .disabled(emailDraft.trimmingCharacters(in: .whitespacesAndNewlines) == savedProfileEmail)

                if !emailStatusMessage.isEmpty {
                    Text(emailStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Language", language)) {
                Picker(localized("App Language", language), selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Button(localized("Save Language", language)) {
                    saveLanguage()
                }
                .disabled(selectedLanguage.rawValue == savedProfileLanguageRawValue)
            }
            .walkthroughTarget(walkthroughFocusTarget == .profileSettings ? .profileSettings : nil)

            Section(localized("Change Password", language)) {
                SecureField(localized("Current password", language), text: $currentPasswordDraft)
                SecureField(localized("New password", language), text: $newPasswordDraft)
                SecureField(localized("Confirm new password", language), text: $confirmPasswordDraft)

                Button(localized("Update Password", language)) {
                    updatePassword()
                }
                .disabled(
                    currentPasswordDraft.isEmpty ||
                    newPasswordDraft.isEmpty ||
                    confirmPasswordDraft.isEmpty
                )

                if !passwordStatusMessage.isEmpty {
                    Text(passwordStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Siri & Shortcuts", language)) {
                Text(localized("Use Siri or the Shortcuts app to run ARCLink actions like adding a personal to-do.", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
            }
        }
        .navigationTitle(localized("My Profile", language))
        .listStyle(.insetGrouped)
        .onAppear {
            emailDraft = savedProfileEmail.isEmpty ? profileEmail : savedProfileEmail
            selectedLanguage = AppLanguage(rawValue: savedProfileLanguageRawValue) ?? .english
        }
    }

    private func saveEmail() {
        let cleanedEmail = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        savedProfileEmail = cleanedEmail
        registeredProfilesRaw = updatingRegisteredProfile(
            rawValue: registeredProfilesRaw,
            accountID: savedProfileAccountID.isEmpty ? profileAccountID : savedProfileAccountID,
            phoneNumber: savedProfilePhoneNumber.isEmpty ? profilePhoneNumber : savedProfilePhoneNumber,
            email: cleanedEmail,
            password: nil,
            language: nil
        )
        emailStatusMessage = cleanedEmail.isEmpty ? "Email removed." : "Email updated."
    }

    private func saveLanguage() {
        savedProfileLanguageRawValue = selectedLanguage.rawValue
        registeredProfilesRaw = updatingRegisteredProfile(
            rawValue: registeredProfilesRaw,
            accountID: savedProfileAccountID.isEmpty ? profileAccountID : savedProfileAccountID,
            phoneNumber: savedProfilePhoneNumber.isEmpty ? profilePhoneNumber : savedProfilePhoneNumber,
            email: nil,
            password: nil,
            language: selectedLanguage
        )
    }

    private func updatePassword() {
        guard currentPasswordDraft == savedProfilePassword else {
            passwordStatusMessage = "Current password is incorrect."
            return
        }
        guard newPasswordDraft.count >= 6 else {
            passwordStatusMessage = "New password must be at least 6 characters."
            return
        }
        guard newPasswordDraft == confirmPasswordDraft else {
            passwordStatusMessage = "New passwords do not match."
            return
        }

        savedProfilePassword = newPasswordDraft
        registeredProfilesRaw = updatingRegisteredProfile(
            rawValue: registeredProfilesRaw,
            accountID: savedProfileAccountID.isEmpty ? profileAccountID : savedProfileAccountID,
            phoneNumber: savedProfilePhoneNumber.isEmpty ? profilePhoneNumber : savedProfilePhoneNumber,
            email: nil,
            password: newPasswordDraft,
            language: nil
        )
        currentPasswordDraft = ""
        newPasswordDraft = ""
        confirmPasswordDraft = ""
        passwordStatusMessage = "Password updated."
    }
}

struct ManagedSectionHostView: View {
    private struct SelectedGroupChatRoute: Identifiable {
        let id: UUID
    }

    let sectionID: UUID
    let walkthroughDestination: DemoDestination
    let walkthroughFocusTarget: WalkthroughTargetID?

    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @State private var selectedGroupChatRoute: SelectedGroupChatRoute?

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    init(
        sectionID: UUID,
        walkthroughDestination: DemoDestination = .home,
        walkthroughFocusTarget: WalkthroughTargetID? = nil
    ) {
        self.sectionID = sectionID
        self.walkthroughDestination = walkthroughDestination
        self.walkthroughFocusTarget = walkthroughFocusTarget
    }

    var body: some View {
        if let sectionBinding {
            sectionDashboardContent(sectionBinding)
        } else {
            Text(localized("Crew not found.", language))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionDashboardContent(_ sectionBinding: Binding<ManagerSection>) -> some View {
        ManagerSectionDashboardView(
            section: sectionBinding,
            walkthroughDestination: walkthroughDestination,
            walkthroughFocusTarget: walkthroughFocusTarget,
            onSave: { },
            onOpenGroupChat: { selectedGroupChatRoute = SelectedGroupChatRoute(id: $0) }
        )
        .sheet(
            item: Binding(
                get: { selectedGroupChatRoute },
                set: { selectedGroupChatRoute = $0 }
            )
        ) { route in
            if let chatBinding = groupChatBinding(for: route.id, section: sectionBinding.wrappedValue) {
                NavigationView {
                    SectionGroupChatDetailView(
                        chat: chatBinding,
                        members: sectionBinding.wrappedValue.members,
                        onSave: { }
                    )
                }
                .navigationViewStyle(.stack)
            }
        }
    }

    @ViewBuilder
    private func groupChatDestination(_ sectionBinding: Binding<ManagerSection>) -> some View {
        if let selectedGroupChatRoute,
           let chatBinding = groupChatBinding(for: selectedGroupChatRoute.id, section: sectionBinding.wrappedValue) {
            SectionGroupChatDetailView(
                chat: chatBinding,
                members: sectionBinding.wrappedValue.members,
                onSave: { }
            )
        } else {
            EmptyView()
        }
    }

    private var sectionBinding: Binding<ManagerSection>? {
        let sections = decodeSections(from: managerSectionsRaw)
        guard sections.contains(where: { $0.id == sectionID }) else { return nil }

        return Binding(
            get: {
                decodeSections(from: managerSectionsRaw).first(where: { $0.id == sectionID }) ?? sections[0]
            },
            set: { updatedSection in
                var currentSections = decodeSections(from: managerSectionsRaw)
                guard let index = currentSections.firstIndex(where: { $0.id == sectionID }) else { return }
                currentSections[index] = updatedSection
                managerSectionsRaw = encodeSections(currentSections)
            }
        )
    }

    private func groupChatBinding(for chatID: UUID, section: ManagerSection) -> Binding<SectionGroupChat>? {
        guard let index = section.groupChats.firstIndex(where: { $0.id == chatID }) else { return nil }
        return Binding(
            get: {
                let sections = decodeSections(from: managerSectionsRaw)
                guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
                      let chatIndex = sections[sectionIndex].groupChats.firstIndex(where: { $0.id == chatID }) else {
                    return section.groupChats[index]
                }
                return sections[sectionIndex].groupChats[chatIndex]
            },
            set: { updatedChat in
                var sections = decodeSections(from: managerSectionsRaw)
                guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
                      let chatIndex = sections[sectionIndex].groupChats.firstIndex(where: { $0.id == chatID }) else { return }
                sections[sectionIndex].groupChats[chatIndex] = updatedChat
                managerSectionsRaw = encodeSections(sections)
            }
        )
    }
}

struct ManagerSectionDashboardView: View {
    private enum SectionTaskTimelineView: String, CaseIterable, Identifiable {
        case month
        case week
        case day

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month:
                return "Month"
            case .week:
                return "Week"
            case .day:
                return "Day"
            }
        }
    }

    private struct PendingPersonalTodo: Identifiable {
        let memberID: UUID
        let todoID: UUID
        let memberName: String
        let todo: MemberTodo

        var id: String { "\(memberID.uuidString)-\(todoID.uuidString)" }
    }

    private struct SectionTaskCalendarDay: Identifiable {
        let id: String
        let date: Date?
        let dayNumber: Int
        let hasTasks: Bool
    }

    @Binding var section: ManagerSection
    let walkthroughDestination: DemoDestination
    let walkthroughFocusTarget: WalkthroughTargetID?
    let onSave: () -> Void
    let onOpenGroupChat: (UUID) -> Void

    @Environment(BluetoothManager.self) private var bluetoothManager
    @State private var showCreateChatSheet = false
    @State private var showSectionSettingsSheet = false
    @State private var showCreateSubsectionSheet = false
    @State private var newChatName = ""
    @State private var selectedGroupChatMemberIDs: Set<UUID> = []
    @State private var newSubsectionName = ""
    @State private var selectedSubsectionMemberIDs: Set<UUID> = []
    @State private var showAssignTaskSheet = false
    @State private var newSectionTaskTitle = ""
    @State private var newSectionTaskDescription = ""
    @State private var newSectionTaskPriority: TaskPriority = .medium
    @State private var newSectionTaskDueDate = Date()
    @State private var newSectionTaskSiteName = ""
    @State private var newSectionTaskLocation = ""
    @State private var newChecklistItemTitle = ""
    @State private var newSectionTaskChecklistItems: [TaskChecklistItem] = []
    @State private var newSectionTaskAttachments: [TaskAttachment] = []
    @State private var newSectionTaskRequiresAcknowledgement = false
    @State private var selectedAssigneeIDs: Set<UUID> = []
    @State private var showTaskAttachmentTypeDialog = false
    @State private var showTaskMediaPicker = false
    @State private var showTaskPDFImporter = false
    @State private var selectedTaskAttachmentType: TaskAttachmentType = .photo
    @State private var sectionTaskViewMode: SectionTaskTimelineView = .month
    @State private var taskSearchText = ""
    @State private var memberSearchText = ""
    @State private var assigneeSearchText = ""
    @State private var selectedSectionTaskDate = Date()
    @State private var selectedSectionTaskWeekAnchor = Date()
    @State private var isSectionSnapshotExpanded = true
    @State private var breakStatusMessage = ""
    @State private var areMembersExpanded = true
    @State private var areSubsectionsExpanded = true
    @State private var walkthroughMemberID: UUID?
    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""
    @AppStorage("profileAccountID") private var profileAccountID = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var subsections: [ManagerSection] {
        decodeSections(from: managerSectionsRaw)
            .filter { $0.parentSectionID == section.id }
            .sorted { $0.name < $1.name }
    }

    private var latestSectionAlert: SectionAlert? {
        section.alerts.sorted { $0.createdAt > $1.createdAt }.first
    }

    private var filteredSectionTasks: [SectionTask] {
        let query = taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return section.sectionTasks }
        let normalizedQuery = query.lowercased()
        return section.sectionTasks.filter { task in
            task.title.lowercased().contains(normalizedQuery) ||
            task.descriptionText.lowercased().contains(normalizedQuery) ||
            task.siteName.lowercased().contains(normalizedQuery) ||
            task.locationDetails.lowercased().contains(normalizedQuery)
        }
    }

    private var filteredMembers: [SectionMember] {
        let query = memberSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return section.members }
        let normalizedQuery = query.lowercased()
        return section.members.filter { member in
            member.name.lowercased().contains(normalizedQuery) ||
            managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw).lowercased().contains(normalizedQuery) ||
            member.roleDisplayTitle.lowercased().contains(normalizedQuery) ||
            member.phoneNumber.contains(query)
        }
    }

    private var filteredAssignableMembers: [SectionMember] {
        let query = assigneeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return section.members }
        let normalizedQuery = query.lowercased()
        return section.members.filter { member in
            member.name.lowercased().contains(normalizedQuery) ||
            managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw).lowercased().contains(normalizedQuery) ||
            member.roleDisplayTitle.lowercased().contains(normalizedQuery) ||
            member.phoneNumber.contains(query)
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            dashboardList
                .navigationTitle(section.name)
                .toolbar { dashboardToolbar }
                .sheet(isPresented: $showSectionSettingsSheet) {
                    sectionSettingsSheet
                }
                .sheet(isPresented: $showCreateSubsectionSheet) {
                    subsectionComposer
                }
                .sheet(isPresented: $showCreateChatSheet) {
                    groupChatComposer
                }
                .sheet(isPresented: $showAssignTaskSheet) {
                    taskComposer
                }
                .sheet(isPresented: $showTaskMediaPicker) {
                    MediaPicker(mediaType: selectedTaskAttachmentType == .video ? .video : .photo) { type, label in
                        let attachmentType: TaskAttachmentType = type == .video ? .video : .photo
                        newSectionTaskAttachments.append(TaskAttachment(type: attachmentType, label: label))
                    }
                }
                .fileImporter(isPresented: $showTaskPDFImporter, allowedContentTypes: [.pdf]) { result in
                    guard case .success(let url) = result else { return }
                    newSectionTaskAttachments.append(TaskAttachment(type: .pdf, label: url.lastPathComponent))
                }
                .confirmationDialog(localized("Add Attachment", language), isPresented: $showTaskAttachmentTypeDialog) {
                    Button(localized("Photo", language)) {
                        selectedTaskAttachmentType = .photo
                        showTaskMediaPicker = true
                    }
                    Button(localized("Video", language)) {
                        selectedTaskAttachmentType = .video
                        showTaskMediaPicker = true
                    }
                    Button("PDF") {
                        showTaskPDFImporter = true
                    }
                    Button(localized("Cancel", language), role: .cancel) { }
                }
                .background(walkthroughMemberNavigationLink)
                .onAppear {
                    applyWalkthroughDestination(walkthroughDestination)
                    scrollToWalkthroughTarget(using: scrollProxy)
                }
                .onChange(of: walkthroughDestination) {
                    applyWalkthroughDestination(walkthroughDestination)
                    scrollToWalkthroughTarget(using: scrollProxy)
                }
                .onChange(of: walkthroughFocusTarget) {
                    scrollToWalkthroughTarget(using: scrollProxy)
                }
        }
    }

    private var dashboardList: some View {
        List {
            if let latestSectionAlert {
                sectionAlertSection(latestSectionAlert)
            }
            sectionInsightsSection
            membersSection
            subsectionsSection
            groupChatsSection
            verificationAndTaskSections
        }
    }

    private func sectionAlertSection(_ alert: SectionAlert) -> some View {
        Section(localized("Alert", language)) {
            VStack(alignment: .leading, spacing: 6) {
                Label(alert.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(alert.message)
                    .font(.body)
                Text(alert.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showSectionSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
            .id(WalkthroughTargetID.sectionFeatureControls.rawValue)
            .walkthroughTarget(.sectionFeatureControls)

            if section.featureSettings.groupChatsEnabled {
                Button {
                    showCreateChatSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var sectionSettingsSheet: some View {
        NavigationView {
            SectionSettingsView(
                section: $section,
                onSave: onSave,
                walkthroughFocusTarget: walkthroughFocusTarget
            )
        }
        .navigationViewStyle(.stack)
    }

    private var sectionInsightsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isSectionSnapshotExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        snapshotBadge(title: localized("Members", language), value: "\(section.members.count)", tint: .blue)
                        snapshotBadge(title: localized("On Site", language), value: "\(section.members.filter(\.isOnSite).count)", tint: .green)
                    }

                HStack {
                    snapshotBadge(title: localized("Due Today", language), value: "\(sectionDueTodayCount)", tint: .orange)
                    snapshotBadge(title: localized("To Verify", language), value: "\(tasksAwaitingVerification.count + personalTodosAwaitingVerification.count)", tint: .red)
                }

                Button {
                    sendBreakTime()
                } label: {
                    Label("Break Time", systemImage: "pause.circle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .overlay {
                    if walkthroughFocusTarget == .sectionBreakTime {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange, lineWidth: 3)
                            .padding(-2)
                    }
                }
                .background {
                    if walkthroughFocusTarget == .sectionBreakTime {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.14))
                    }
                }
                .disabled(!bluetoothManager.isConnected())
                .id(WalkthroughTargetID.sectionBreakTime.rawValue)
                .walkthroughTarget(walkthroughFocusTarget == .sectionBreakTime ? .sectionBreakTime : nil)

                if !breakStatusMessage.isEmpty {
                    Text(breakStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(localized("Completion Overview", language))
                    .font(.headline)

                    ForEach(section.members) { member in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(memberCompletedAssignments(member))/\(memberAssignedAssignments(member))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            stackedProgressBar(
                                completed: memberCompletedAssignments(member),
                                pendingVerification: memberPendingVerificationAssignments(member),
                                total: memberAssignedAssignments(member)
                            )

                            HStack {
                                Text("\(localized("Tasks", language)): \(completedSectionTaskCount(for: member.id))/\(assignedSectionTaskCount(for: member.id))")
                                Spacer()
                                Text("\(localized("To-Dos", language)): \(completedPersonalTodoCount(for: member))/\(member.todos.count)")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Text(localized("Crew Snapshot", language))
            }
        }
        .id(WalkthroughTargetID.sectionSnapshot.rawValue)
        .walkthroughTarget(.sectionSnapshot)
    }

    private var subsectionComposer: some View {
        NavigationView {
            Form {
                Section(localized("New Sub-crew", language)) {
                    TextField(localized("Sub-crew name", language), text: $newSubsectionName)
                        .textInputAutocapitalization(.words)
                }

                Section(localized("Add Members", language)) {
                    if section.members.isEmpty {
                        Text(localized("No members in parent section.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(section.members) { member in
                            Button {
                                toggleSubsectionMember(member.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                        Text(member.roleDisplayTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selectedSubsectionMemberIDs.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedSubsectionMemberIDs.contains(member.id) ? .green : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button(localized("Create Sub-crew", language)) {
                        createSubsection()
                    }
                    .disabled(newSubsectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(localized("Create Sub-crew", language))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localized("Cancel", language)) {
                        showCreateSubsectionSheet = false
                        newSubsectionName = ""
                        selectedSubsectionMemberIDs = []
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var groupChatComposer: some View {
        NavigationView {
            Form {
                Section(localized("New Group Chat", language)) {
                    TextField(localized("Group chat name", language), text: $newChatName)
                        .textInputAutocapitalization(.words)
                }

                Section(localized("Add Members", language)) {
                    if section.members.isEmpty {
                        Text(localized("No section members available yet.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        Button(localized("Add All", language)) {
                            selectAllGroupChatMembers()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedGroupChatMemberIDs.count == section.members.count)

                        ForEach(section.members) { member in
                            Button {
                                toggleGroupChatMember(member.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                        Text(member.roleDisplayTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedGroupChatMemberIDs.contains(member.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button(localized("Create Group Chat", language)) {
                        createGroupChat()
                    }
                    .disabled(newChatName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(localized("Create Group Chat", language))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localized("Cancel", language)) {
                        showCreateChatSheet = false
                        newChatName = ""
                        selectedGroupChatMemberIDs = []
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var taskComposer: some View {
        NavigationView {
            Form {
                Section(localized("Task Details", language)) {
                    TextField(localized("Task title", language), text: $newSectionTaskTitle)
                        .textInputAutocapitalization(.sentences)

                    TextEditor(text: $newSectionTaskDescription)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if newSectionTaskDescription.isEmpty {
                                Text(localized("Description (use keyboard or dictation)", language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                            }
                        }

                    Picker(localized("Priority", language), selection: $newSectionTaskPriority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }

                    DatePicker(
                        localized("Due Date", language),
                        selection: $newSectionTaskDueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    TextField(localized("Site", language), text: $newSectionTaskSiteName)
                        .textInputAutocapitalization(.words)

                    TextField(localized("Location (optional)", language), text: $newSectionTaskLocation)
                        .textInputAutocapitalization(.words)

                    Toggle(localized("Requires acknowledgement", language), isOn: $newSectionTaskRequiresAcknowledgement)
                }

                Section(localized("Checklist Items", language)) {
                    HStack {
                        TextField(localized("Checklist item", language), text: $newChecklistItemTitle)
                            .textInputAutocapitalization(.sentences)

                        Button(localized("Add", language)) {
                            addChecklistItem()
                        }
                        .disabled(newChecklistItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if newSectionTaskChecklistItems.isEmpty {
                        Text(localized("No checklist items yet.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(newSectionTaskChecklistItems) { item in
                            HStack {
                                Text(item.title)
                                Spacer()
                                Button(localized("Delete", language), role: .destructive) {
                                    newSectionTaskChecklistItems.removeAll(where: { $0.id == item.id })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section(localized("Attachments", language)) {
                    Button(localized("Add Attachment", language)) {
                        showTaskAttachmentTypeDialog = true
                    }

                    if newSectionTaskAttachments.isEmpty {
                        Text(localized("No attachments yet.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(newSectionTaskAttachments) { attachment in
                            HStack {
                                Label(attachment.label, systemImage: attachment.type.systemImage)
                                Spacer()
                                Button(localized("Delete", language), role: .destructive) {
                                    newSectionTaskAttachments.removeAll(where: { $0.id == attachment.id })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section(localized("Assign To", language)) {
                    if section.members.isEmpty {
                        Text(localized("No section members available.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        TextField(localized("Search crew members", language), text: $assigneeSearchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(localized("Add All", language)) {
                            selectAllAssignees(filteredAssignableMembers)
                        }
                        .buttonStyle(.bordered)
                        .disabled(filteredAssignableMembers.allSatisfy { selectedAssigneeIDs.contains($0.id) })

                        if filteredAssignableMembers.isEmpty {
                            Text(localized("No matching crew members.", language))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredAssignableMembers) { member in
                            Button {
                                toggleAssignee(member.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                        Text(member.roleDisplayTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedAssigneeIDs.contains(member.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        }
                    }
                }

                Section {
                    Button(localized("Create Task", language)) {
                        createSectionTask()
                    }
                    .walkthroughTarget(walkthroughFocusTarget == .sectionTaskAddButton ? .sectionTaskAddButton : nil)
                    .disabled(
                        newSectionTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        selectedAssigneeIDs.isEmpty
                    )
                }
            }
            .navigationTitle(localized("Assign Task", language))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localized("Cancel", language)) {
                        resetTaskComposer()
                        showAssignTaskSheet = false
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var membersSection: some View {
        Section(localized("Members", language)) {
            DisclosureGroup(isExpanded: $areMembersExpanded) {
                if section.members.isEmpty {
                    Text(localized("No crews have joined this section yet.", language))
                        .foregroundStyle(.secondary)
                } else {
                    TextField(localized("Search crew members", language), text: $memberSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if filteredMembers.isEmpty {
                        Text(localized("No matching crew members.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredMembers) { member in
                            if let memberBinding = memberBinding(for: member.id) {
                                NavigationLink {
                                    MemberDetailView(
                                        member: memberBinding,
                                        sectionTasks: section.sectionTasks,
                                        onSave: onSave
                                    )
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                                .font(.headline)
                                            Spacer()
                                            Text(member.roleDisplayTitle)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack {
                                            Text(member.phoneNumber)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Label(
                                                member.isOnSite ? localized("On Site", language) : localized("Off Site", language),
                                                systemImage: member.isOnSite ? "checkmark.seal.fill" : "xmark.seal"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(member.isOnSite ? .green : .secondary)
                                        }
                                        Text("\(localized("Crew tasks", language)): \(assignedSectionTaskCount(for: member.id)) • \(localized("Personal to-dos", language)): \(member.todos.count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("\(localized("Completed", language)): \(completedSectionTaskCount(for: member.id))/\(assignedSectionTaskCount(for: member.id))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                Text(localized("Show Members", language))
            }
        }
        .id(WalkthroughTargetID.sectionMembers.rawValue)
        .walkthroughTarget(.sectionMembers)
    }

    private var subsectionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $areSubsectionsExpanded) {
                if subsections.isEmpty {
                    Text(localized("No sub-crews yet.", language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subsections) { subsection in
                        NavigationLink {
                            ManagedSectionHostView(sectionID: subsection.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(subsection.name)
                                        .font(.headline)
                                    Spacer()
                                    Label(subsection.codeWord, systemImage: "link")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(subsection.members.count) crews • \(subsection.groupChats.count) group chats")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } label: {
                Text(localized("Show Sub-crews", language))
            }
        } header: {
            HStack {
                Text(localized("Sub-crews", language))
                Spacer()
                Button {
                    newSubsectionName = ""
                    selectedSubsectionMemberIDs = []
                    showCreateSubsectionSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .id(WalkthroughTargetID.sectionSubsections.rawValue)
        .walkthroughTarget(.sectionSubsections)
    }

    @ViewBuilder
    private var groupChatsSection: some View {
        if section.featureSettings.groupChatsEnabled {
            Section(localized("Group Chats", language)) {
                if section.groupChats.isEmpty {
                    Text(localized("No group chats yet. Tap + to create one.", language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(section.groupChats) { chat in
                        Button {
                            onOpenGroupChat(chat.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chat.name)
                                    .font(.headline)
                                Text(latestMessagePreview(for: chat))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteGroupChats)
                }
            }
            .id(WalkthroughTargetID.sectionChats.rawValue)
            .walkthroughTarget(.sectionChats)
        }
    }

    @ViewBuilder
    private var verificationAndTaskSections: some View {
        if section.featureSettings.sectionTasksEnabled || section.featureSettings.personalTodosEnabled {
            if !tasksAwaitingVerification.isEmpty || !personalTodosAwaitingVerification.isEmpty {
                Section(localized("To Verify", language)) {
                    ForEach(tasksAwaitingVerification) { task in
                        managerTaskNavigationRow(task)
                    }
                    ForEach(personalTodosAwaitingVerification) { item in
                        managerPersonalTodoVerificationRow(item)
                    }
                }
                .id(WalkthroughTargetID.sectionVerification.rawValue)
                .walkthroughTarget(.sectionVerification)
            }

            if section.featureSettings.sectionTasksEnabled {
                sectionTasksSection
            }
        }
    }

    private var sectionTasksSection: some View {
        Section {
            TextField(localized("Search tasks", language), text: $taskSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if filteredSectionTasks.isEmpty {
                Text(taskSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localized("No section tasks yet.", language) : localized("No matching tasks.", language))
                    .foregroundStyle(.secondary)
            } else {
                Picker(localized("Task View", language), selection: $sectionTaskViewMode) {
                    ForEach(SectionTaskTimelineView.allCases) { mode in
                        Text(localized(mode.title, language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch sectionTaskViewMode {
                case .month:
                    sectionTaskCalendarView
                        .id(WalkthroughTargetID.sectionTasks.rawValue)
                        .walkthroughTarget(.sectionTasks)

                    let dailyTasks = sectionTasks(on: selectedSectionTaskDate)
                    if dailyTasks.isEmpty {
                        Text(localized("No tasks on this date.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dailyTasks) { task in
                            managerTaskNavigationRow(task)
                        }
                    }
                case .week:
                    DatePicker(
                        localized("Week Of", language),
                        selection: $selectedSectionTaskWeekAnchor,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)

                    let weeklyBuckets = sectionTasksForSelectedWeek()
                    if weeklyBuckets.isEmpty {
                        Text(localized("No tasks in this week.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(weeklyBuckets, id: \.date) { bucket in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(weekHeaderString(for: bucket.date))
                                    .font(.subheadline.weight(.semibold))
                                ForEach(bucket.tasks) { task in
                                    managerTaskNavigationRow(task)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                case .day:
                    DatePicker(
                        localized("Day", language),
                        selection: $selectedSectionTaskDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)

                    let dailyTasks = sectionTasks(on: selectedSectionTaskDate)
                    if dailyTasks.isEmpty {
                        Text(localized("No tasks on this day.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dailyTasks) { task in
                            managerTaskNavigationRow(task)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(localized("Crew Tasks", language))
                Spacer()
                Button {
                    showAssignTaskSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .id(WalkthroughTargetID.sectionTaskAddButton.rawValue)
                .walkthroughTarget(.sectionTaskAddButton)
            }
        }
    }

    private var sectionTaskCalendarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    shiftSelectedSectionTaskMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(sectionTaskMonthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    shiftSelectedSectionTaskMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(sectionTaskWeekdayHeaders, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(sectionTaskCalendarWeeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 8) {
                        ForEach(week) { day in
                            if let date = day.date {
                                Button {
                                    selectedSectionTaskDate = date
                                } label: {
                                    VStack(spacing: 4) {
                                        Text("\(day.dayNumber)")
                                            .font(.subheadline.weight(Calendar.current.isDate(date, inSameDayAs: selectedSectionTaskDate) ? .bold : .regular))
                                            .frame(maxWidth: .infinity)
                                        Circle()
                                            .fill(day.hasTasks ? Color.arcAccentOrange : Color.clear)
                                            .frame(width: 6, height: 6)
                                    }
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Calendar.current.isDate(date, inSameDayAs: selectedSectionTaskDate) ? Color.arcAccentOrange.opacity(0.16) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var sectionTaskCalendarWeeks: [[SectionTaskCalendarDay]] {
        let days = sectionTaskCalendarDays
        return stride(from: 0, to: days.count, by: 7).map { startIndex in
            Array(days[startIndex..<min(startIndex + 7, days.count)])
        }
    }

    @ViewBuilder
    private var walkthroughMemberNavigationLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { walkthroughMemberID != nil },
                set: { isActive in
                    if !isActive {
                        walkthroughMemberID = nil
                    }
                }
            ),
            destination: {
                if let walkthroughMemberBinding {
                    MemberDetailView(
                        member: walkthroughMemberBinding,
                        sectionTasks: section.sectionTasks,
                        onSave: onSave,
                        walkthroughFocusTarget: walkthroughFocusTarget
                    )
                }
            },
            label: { EmptyView() }
        )
        .hidden()
    }

    private func createGroupChat() {
        let cleanedName = newChatName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        section.groupChats.insert(
            SectionGroupChat(
                name: cleanedName,
                createdAt: shortDateString(),
                participantMemberIDs: Array(selectedGroupChatMemberIDs),
                writableMemberIDs: Array(selectedGroupChatMemberIDs),
                messages: [
                    GroupChatMessage(
                        sender: "System",
                        text: "Group chat created.",
                        time: shortTimeString()
                    )
                ]
            ),
            at: 0
        )
        onSave()

        newChatName = ""
        selectedGroupChatMemberIDs = []
        showCreateChatSheet = false
    }

    private func toggleGroupChatMember(_ memberID: UUID) {
        if selectedGroupChatMemberIDs.contains(memberID) {
            selectedGroupChatMemberIDs.remove(memberID)
        } else {
            selectedGroupChatMemberIDs.insert(memberID)
        }
    }

    private func deleteGroupChats(at offsets: IndexSet) {
        section.groupChats.remove(atOffsets: offsets)
        onSave()
    }

    private func toggleAssignee(_ memberID: UUID) {
        if selectedAssigneeIDs.contains(memberID) {
            selectedAssigneeIDs.remove(memberID)
        } else {
            selectedAssigneeIDs.insert(memberID)
        }
    }

    private func selectAllGroupChatMembers() {
        selectedGroupChatMemberIDs = Set(section.members.map(\.id))
    }

    private func selectAllAssignees(_ members: [SectionMember]? = nil) {
        let membersToSelect = members ?? section.members
        selectedAssigneeIDs.formUnion(membersToSelect.map(\.id))
    }

    private func toggleSubsectionMember(_ memberID: UUID) {
        if selectedSubsectionMemberIDs.contains(memberID) {
            selectedSubsectionMemberIDs.remove(memberID)
        } else {
            selectedSubsectionMemberIDs.insert(memberID)
        }
    }

    private func createSubsection() {
        let cleanedName = newSubsectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return }

        let allSections = decodeSections(from: managerSectionsRaw)
        let existingCodes = Set(allSections.map(\.codeWord))
        let selectedMembers = section.members.filter { selectedSubsectionMemberIDs.contains($0.id) }
        let subsection = ManagerSection(
            ownerAccountID: profileAccountID.isEmpty ? section.ownerAccountID : profileAccountID,
            parentSectionID: section.id,
            name: cleanedName,
            codeWord: randomSiteCodeWord(existingCodes: existingCodes),
            featureSettings: section.featureSettings,
            members: selectedMembers
        )

        managerSectionsRaw = encodeSections(allSections + [subsection])
        showCreateSubsectionSheet = false
        newSubsectionName = ""
        selectedSubsectionMemberIDs = []
    }

    private func createSectionTask() {
        let cleanedTitle = newSectionTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, !selectedAssigneeIDs.isEmpty else { return }

        section.sectionTasks.insert(
            SectionTask(
                title: cleanedTitle,
                descriptionText: newSectionTaskDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                priority: newSectionTaskPriority,
                dueDate: newSectionTaskDueDate,
                siteName: newSectionTaskSiteName.trimmingCharacters(in: .whitespacesAndNewlines),
                locationDetails: newSectionTaskLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                checklistItems: newSectionTaskChecklistItems,
                attachments: newSectionTaskAttachments,
                requiresAcknowledgement: newSectionTaskRequiresAcknowledgement,
                assigneeIDs: Array(selectedAssigneeIDs)
            ),
            at: 0
        )
        onSave()
        resetTaskComposer()
        showAssignTaskSheet = false
    }

    private func deleteSectionTask(_ id: UUID) {
        section.sectionTasks.removeAll(where: { $0.id == id })
        onSave()
    }

    private func assigneeSummary(for ids: [UUID]) -> String {
        let names = section.members
            .filter { ids.contains($0.id) }
            .map { managerVisibleName($0, nicknamesRaw: managerCrewNicknamesRaw) }
        if names.isEmpty { return "None" }
        return names.joined(separator: ", ")
    }

    private func assignedSectionTaskCount(for memberID: UUID) -> Int {
        section.sectionTasks.filter { $0.assigneeIDs.contains(memberID) }.count
    }

    private func completedSectionTaskCount(for memberID: UUID) -> Int {
        section.sectionTasks.filter { finalCompletionMemberIDs(for: $0).contains(memberID) }.count
    }

    private var sectionDueTodayCount: Int {
        let calendar = Calendar.current
        let sectionTasks = section.sectionTasks.filter { calendar.isDateInToday($0.dueDate) }.count
        let todos = section.members.flatMap(\.todos).filter { calendar.isDateInToday($0.dueDate) }.count
        return sectionTasks + todos
    }

    private func completedPersonalTodoCount(for member: SectionMember) -> Int {
        member.todos.filter { personalTodoIsCompleted($0) }.count
    }

    private func memberAssignedAssignments(_ member: SectionMember) -> Int {
        assignedSectionTaskCount(for: member.id) + member.todos.count
    }

    private func memberCompletedAssignments(_ member: SectionMember) -> Int {
        completedSectionTaskCount(for: member.id) + completedPersonalTodoCount(for: member)
    }

    private func memberPendingVerificationAssignments(_ member: SectionMember) -> Int {
        let taskCount = section.sectionTasks.filter {
            $0.requiresAcknowledgement &&
            $0.assigneeIDs.contains(member.id) &&
            $0.doneMemberIDs.contains(member.id) &&
            !$0.verifiedMemberIDs.contains(member.id)
        }.count
        let todoCount = member.todos.filter {
            $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
        }.count
        return taskCount + todoCount
    }

    private func sendBreakTime() {
        guard bluetoothManager.isConnected() else {
            breakStatusMessage = "Bluetooth not connected."
            return
        }

        do {
            let payload: [String: String] = [
                "type": "break_time",
                "priority": "medium",
                "title": "Break Time",
                "message": "Break time. Pause work and follow section break procedures."
            ]

            let data = try JSONSerialization.data(withJSONObject: payload)
            let json = String(data: data, encoding: .utf8) ?? ""

            try bluetoothManager.writeString(json)

            breakStatusMessage = "Break time sent."

        } catch {
            breakStatusMessage = "Failed to send break time."
        }
    }

    private func personalTodoIsCompleted(_ todo: MemberTodo) -> Bool {
        todo.requiresAcknowledgement ? todo.isCompleted : todo.isMarkedDone
    }

    private func snapshotBadge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stackedProgressBar(completed: Int, pendingVerification: Int, total: Int) -> some View {
        let remaining = max(total - completed - pendingVerification, 0)
        let safeTotal = max(total, 1)

        return GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: proxy.size.width * CGFloat(completed) / CGFloat(safeTotal))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: proxy.size.width * CGFloat(pendingVerification) / CGFloat(safeTotal))
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: proxy.size.width * CGFloat(remaining) / CGFloat(safeTotal))
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func resetTaskComposer() {
        newSectionTaskTitle = ""
        newSectionTaskDescription = ""
        newSectionTaskPriority = .medium
        newSectionTaskDueDate = Date()
        newSectionTaskSiteName = section.name
        newSectionTaskLocation = ""
        newChecklistItemTitle = ""
        newSectionTaskChecklistItems = []
        newSectionTaskAttachments = []
        newSectionTaskRequiresAcknowledgement = false
        selectedAssigneeIDs = []
    }

    private func sectionTasks(on date: Date) -> [SectionTask] {
        filteredSectionTasks
            .filter { Calendar.current.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var sectionTaskMonthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: startOfMonth(for: selectedSectionTaskDate))
    }

    private var sectionTaskWeekdayHeaders: [String] {
        let formatter = DateFormatter()
        return formatter.shortStandaloneWeekdaySymbols
    }

    private var sectionTaskDates: Set<Date> {
        let calendar = Calendar.current
        return Set(filteredSectionTasks.map { calendar.startOfDay(for: $0.dueDate) })
    }

    private var sectionTaskCalendarDays: [SectionTaskCalendarDay] {
        let calendar = Calendar.current
        let monthStart = startOfMonth(for: selectedSectionTaskDate)
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<2
        let firstWeekdayIndex = calendar.component(.weekday, from: monthStart) - calendar.firstWeekday
        let leadingEmptyDays = (firstWeekdayIndex + 7) % 7
        var days: [SectionTaskCalendarDay] = (0..<leadingEmptyDays).map { index in
            SectionTaskCalendarDay(id: "empty-\(index)", date: nil, dayNumber: 0, hasTasks: false)
        }

        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            days.append(
                SectionTaskCalendarDay(
                    id: "day-\(day)",
                    date: date,
                    dayNumber: day,
                    hasTasks: sectionTaskDates.contains(calendar.startOfDay(for: date))
                )
            )
        }

        while days.count % 7 != 0 {
            days.append(
                SectionTaskCalendarDay(
                    id: "trailing-empty-\(days.count)",
                    date: nil,
                    dayNumber: 0,
                    hasTasks: false
                )
            )
        }

        return days
    }

    private func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private func shiftSelectedSectionTaskMonth(by offset: Int) {
        guard let shiftedDate = Calendar.current.date(byAdding: .month, value: offset, to: startOfMonth(for: selectedSectionTaskDate)) else {
            return
        }
        selectedSectionTaskDate = shiftedDate
    }

    private func sectionTasksForSelectedWeek() -> [(date: Date, tasks: [SectionTask])] {
        let start = startOfWeek(for: selectedSectionTaskWeekAnchor)
        return (0..<7).compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: start) else { return nil }
            let tasks = sectionTasks(on: day)
            return tasks.isEmpty ? nil : (day, tasks)
        }
    }

    private var tasksAwaitingVerification: [SectionTask] {
        filteredSectionTasks.filter { task in
            task.requiresAcknowledgement && task.doneMemberIDs.contains(where: { !task.verifiedMemberIDs.contains($0) })
        }
    }

    private var personalTodosAwaitingVerification: [PendingPersonalTodo] {
        section.members.flatMap { member in
            member.todos.compactMap { todo in
                guard todo.requiresAcknowledgement, todo.isMarkedDone, !todo.isCompleted else { return nil }
                return PendingPersonalTodo(
                    memberID: member.id,
                    todoID: todo.id,
                    memberName: managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw),
                    todo: todo
                )
            }
        }
        .sorted { $0.todo.dueDate < $1.todo.dueDate }
    }

    private func finalCompletionMemberIDs(for task: SectionTask) -> [UUID] {
        task.requiresAcknowledgement ? task.verifiedMemberIDs : task.doneMemberIDs
    }

    private func addChecklistItem() {
        let cleanedTitle = newChecklistItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        newSectionTaskChecklistItems.append(TaskChecklistItem(title: cleanedTitle))
        newChecklistItemTitle = ""
    }

    @ViewBuilder
    private func sectionTaskRow(_ task: SectionTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.title)
                    .font(.headline)
                Spacer()
                Text(task.priority.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(task.priority.color.opacity(0.18), in: Capsule())
            }

            Text("Due \(task.dueDate.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !task.siteName.isEmpty || !task.locationDetails.isEmpty {
                Text("\(task.siteName)\(task.locationDetails.isEmpty ? "" : " • \(task.locationDetails)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Assigned: \(assigneeSummary(for: task.assigneeIDs))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(localized("Status", language)): \(taskStatusSummary(task))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Completed: \(finalCompletionMemberIDs(for: task).count)/\(task.assigneeIDs.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func taskStatusSummary(_ task: SectionTask) -> String {
        if task.requiresAcknowledgement, task.doneMemberIDs.contains(where: { !task.verifiedMemberIDs.contains($0) }) {
            return localized("To Verify", language)
        }
        if finalCompletionMemberIDs(for: task).count == task.assigneeIDs.count, !task.assigneeIDs.isEmpty {
            return localized("Verified", language)
        }
        if !task.doneMemberIDs.isEmpty {
            return localized("Done", language)
        }
        return localized("Assigned", language)
    }

    private func weekHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func taskBinding(for taskID: UUID) -> Binding<SectionTask>? {
        guard let index = section.sectionTasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        return $section.sectionTasks[index]
    }

    private func memberBinding(for memberID: UUID) -> Binding<SectionMember>? {
        guard let index = section.members.firstIndex(where: { $0.id == memberID }) else { return nil }
        return $section.members[index]
    }

    private func groupChatBinding(for chatID: UUID) -> Binding<SectionGroupChat>? {
        guard let index = section.groupChats.firstIndex(where: { $0.id == chatID }) else { return nil }
        return $section.groupChats[index]
    }

    private var walkthroughMemberBinding: Binding<SectionMember>? {
        guard let walkthroughMemberID,
              let index = section.members.firstIndex(where: { $0.id == walkthroughMemberID }) else { return nil }
        return $section.members[index]
    }

    private func scrollToWalkthroughTarget(using scrollProxy: ScrollViewProxy) {
        guard let walkthroughFocusTarget else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(walkthroughFocusTarget.rawValue, anchor: .center)
            }
        }
    }

    private func applyWalkthroughDestination(_ destination: DemoDestination) {
        if walkthroughFocusTarget == .sectionSnapshot || walkthroughFocusTarget == .sectionBreakTime {
            isSectionSnapshotExpanded = true
        }

        if walkthroughFocusTarget == .sectionSubsections {
            areSubsectionsExpanded = true
        }

        switch destination {
        case .sectionTasks(let sectionID) where sectionID == section.id:
            areSubsectionsExpanded = false
            areMembersExpanded = false
            sectionTaskViewMode = .month
            showSectionSettingsSheet = false
            walkthroughMemberID = nil
            showAssignTaskSheet = false
        case .sectionChats(let sectionID) where sectionID == section.id:
            areSubsectionsExpanded = false
            areMembersExpanded = false
            showAssignTaskSheet = false
            showSectionSettingsSheet = false
            walkthroughMemberID = nil
        case .sectionMembers(let sectionID) where sectionID == section.id:
            areSubsectionsExpanded = false
            areMembersExpanded = true
            showAssignTaskSheet = false
            showSectionSettingsSheet = false
            walkthroughMemberID = nil
        case .sectionTimeClock(let sectionID) where sectionID == section.id:
            areSubsectionsExpanded = false
            areMembersExpanded = true
            showAssignTaskSheet = false
            showSectionSettingsSheet = false
            walkthroughMemberID = section.members.first?.id
        case .sectionSettings(let sectionID) where sectionID == section.id:
            areSubsectionsExpanded = false
            showAssignTaskSheet = false
            walkthroughMemberID = nil
            showSectionSettingsSheet = true
        case .sectionDetail(let sectionID) where sectionID == section.id:
            showAssignTaskSheet = false
            showSectionSettingsSheet = false
            walkthroughMemberID = nil
        default:
            break
        }
    }

    private func latestMessagePreview(for chat: SectionGroupChat) -> String {
        guard let lastMessage = chat.messages.last else { return "No messages yet." }
        if lastMessage.messageType == .text {
            return "\(lastMessage.sender): \(lastMessage.text)"
        }
        let mediaLabel = lastMessage.messageType == .photo ? "Photo" : "Video"
        return "\(lastMessage.sender): \(mediaLabel)"
    }

    @ViewBuilder
    private func managerTaskNavigationRow(_ task: SectionTask) -> some View {
        if let taskBinding = taskBinding(for: task.id) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    verifyPendingTaskMembers(taskID: task.id)
                } label: {
                    Image(systemName: verificationButtonImage(for: task))
                        .font(.title3)
                        .foregroundStyle(verificationButtonColor(for: task))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .disabled(!canVerifyFromRow(task))

                NavigationLink {
                    ManagerSectionTaskDetailView(
                        task: taskBinding,
                        members: section.members,
                        onSave: onSave
                    )
                } label: {
                    sectionTaskRow(task)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        deleteSectionTask(task.id)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Button {
                } label: {
                    Image(systemName: verificationButtonImage(for: task))
                        .font(.title3)
                        .foregroundStyle(verificationButtonColor(for: task))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .disabled(true)

                sectionTaskRow(task)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            deleteSectionTask(task.id)
                        }
                    }
            }
        }
    }

    private func canVerifyFromRow(_ task: SectionTask) -> Bool {
        task.requiresAcknowledgement && task.doneMemberIDs.contains(where: { !task.verifiedMemberIDs.contains($0) })
    }

    private func verificationButtonImage(for task: SectionTask) -> String {
        if task.requiresAcknowledgement {
            if canVerifyFromRow(task) {
                return "clock.badge.checkmark.fill"
            }
            if finalCompletionMemberIDs(for: task).count == task.assigneeIDs.count, !task.assigneeIDs.isEmpty {
                return "checkmark.circle.fill"
            }
            return "circle"
        }

        if finalCompletionMemberIDs(for: task).count == task.assigneeIDs.count, !task.assigneeIDs.isEmpty {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private func verificationButtonColor(for task: SectionTask) -> Color {
        if task.requiresAcknowledgement && canVerifyFromRow(task) {
            return .orange
        }
        if finalCompletionMemberIDs(for: task).count == task.assigneeIDs.count, !task.assigneeIDs.isEmpty {
            return .green
        }
        return .secondary
    }

    private func verifyPendingTaskMembers(taskID: UUID) {
        guard let index = section.sectionTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let doneMemberIDs = section.sectionTasks[index].doneMemberIDs
        let alreadyVerified = Set(section.sectionTasks[index].verifiedMemberIDs)
        let pendingVerification = doneMemberIDs.filter { !alreadyVerified.contains($0) }
        guard !pendingVerification.isEmpty else { return }
        section.sectionTasks[index].verifiedMemberIDs.append(contentsOf: pendingVerification)
        onSave()
    }

    @ViewBuilder
    private func managerPersonalTodoVerificationRow(_ item: PendingPersonalTodo) -> some View {
        if let todoBinding = memberTodoBinding(memberID: item.memberID, todoID: item.todoID) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    todoBinding.wrappedValue.isCompleted = true
                    onSave()
                } label: {
                    Image(systemName: item.todo.isCompleted ? "checkmark.circle.fill" : "clock.badge.checkmark.fill")
                        .font(.title3)
                        .foregroundStyle(item.todo.isCompleted ? .green : .orange)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                NavigationLink {
                    ManagerMemberTodoDetailView(todo: todoBinding, onSave: onSave)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.todo.title)
                                .font(.headline)
                            Spacer()
                            Text(item.todo.priority.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(item.todo.priority.color.opacity(0.18), in: Capsule())
                        }

                        Text("\(localized("From", language)): \(item.memberName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("\(localized("Due", language)) \(item.todo.dueDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(localized("To Verify", language))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func memberTodoBinding(memberID: UUID, todoID: UUID) -> Binding<MemberTodo>? {
        guard let memberIndex = section.members.firstIndex(where: { $0.id == memberID }),
              let todoIndex = section.members[memberIndex].todos.firstIndex(where: { $0.id == todoID }) else { return nil }
        return $section.members[memberIndex].todos[todoIndex]
    }
}

struct SectionSettingsView: View {
    @Binding var section: ManagerSection
    let onSave: () -> Void
    let walkthroughFocusTarget: WalkthroughTargetID?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("registeredProfilesJSON") private var registeredProfilesRaw = ""
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""
    @State private var manualMemberAccountID = ""
    @State private var manualAddStatusMessage = ""
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var sectionNameDraft = ""
    @State private var codeWordDraft = ""
    @State private var sectionIdentityStatusMessage = ""
    @State private var areSettingsMembersExpanded = false

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var parentSection: ManagerSection? {
        guard let parentSectionID = section.parentSectionID else { return nil }
        return decodeSections(from: managerSectionsRaw).first(where: { $0.id == parentSectionID })
    }

    private var availableParentMembers: [SectionMember] {
        guard let parentSection else { return [] }
        return parentSection.members.filter { parentMember in
            !section.members.contains(where: { $0.phoneNumber == parentMember.phoneNumber })
        }
    }

    init(
        section: Binding<ManagerSection>,
        onSave: @escaping () -> Void,
        walkthroughFocusTarget: WalkthroughTargetID? = nil
    ) {
        _section = section
        self.onSave = onSave
        self.walkthroughFocusTarget = walkthroughFocusTarget
    }

    var body: some View {
        Form {
            Section(localized("Crew Details", language)) {
                TextField(localized("Crew name", language), text: $sectionNameDraft)
                    .textInputAutocapitalization(.words)

                TextField(localized("Crew code word", language), text: $codeWordDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button(localized("Save Section Details", language)) {
                    saveSectionIdentity()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    sectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    normalizeCodeWord(codeWordDraft).isEmpty
                )

                if !sectionIdentityStatusMessage.isEmpty {
                    Text(sectionIdentityStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Code Word", language)) {
                HStack {
                    Text(localized("Code Word", language))
                    Spacer()
                    Text(section.codeWord)
                        .font(.subheadline.weight(.semibold))
                }

                HStack(spacing: 12) {
                    Button(localized("Copy Code", language)) {
                        UIPasteboard.general.string = section.codeWord
                    }
                    .buttonStyle(.bordered)

                    Button(localized("Share Code", language)) {
                        shareText = "Join \(section.name) with code word: \(section.codeWord)"
                        showShareSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section(localized("Add Members", language)) {
                if section.parentSectionID == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(localized("Account ID number", language), text: $manualMemberAccountID)
                            .keyboardType(.numberPad)

                        Button(localized("Add Member by ID", language)) {
                            addMemberByAccountID()
                        }
                        .buttonStyle(.bordered)
                        .disabled(manualMemberAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !manualAddStatusMessage.isEmpty {
                            Text(manualAddStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if availableParentMembers.isEmpty {
                    Text(localized("No additional parent section members available.", language))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(availableParentMembers) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                        .font(.headline)
                                    Text(member.phoneNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(localized("Add", language)) {
                                    addMemberFromParent(member)
                                }
                            }
                        }

                        if !manualAddStatusMessage.isEmpty {
                            Text(manualAddStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(localized("Remove Members", language)) {
                DisclosureGroup(isExpanded: $areSettingsMembersExpanded) {
                    if section.members.isEmpty {
                        Text(localized("No members in this section.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(section.members) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                        .font(.headline)
                                    Text(member.phoneNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(localized("Remove", language), role: .destructive) {
                                    removeMember(member.id)
                                }
                            }
                        }
                    }
                } label: {
                    Text(localized("Show Members", language))
                }
            }

            Section(localized("Crew Features", language)) {
                Toggle(localized("Enable Time Clock", language), isOn: featureBinding(\.timeClockEnabled))
                Toggle(localized("Enable Group Chats", language), isOn: featureBinding(\.groupChatsEnabled))
                Toggle(localized("Enable Section Tasks", language), isOn: featureBinding(\.sectionTasksEnabled))
                Toggle(localized("Enable Personal To-Dos", language), isOn: featureBinding(\.personalTodosEnabled))
            }
            .walkthroughTarget(walkthroughFocusTarget == .sectionFeatureControls ? .sectionFeatureControls : nil)
        }
        .onAppear {
            sectionNameDraft = section.name
            codeWordDraft = section.codeWord
        }
        .navigationTitle(localized("Crew Settings", language))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(localized("Done", language)) {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareText])
        }
    }

    private func featureBinding(_ keyPath: WritableKeyPath<SectionFeatureSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { section.featureSettings[keyPath: keyPath] },
            set: { newValue in
                section.featureSettings[keyPath: keyPath] = newValue
                onSave()
            }
        )
    }

    private func removeMember(_ memberID: UUID) {
        section.members.removeAll(where: { $0.id == memberID })

        for index in section.groupChats.indices {
            section.groupChats[index].participantMemberIDs.removeAll(where: { $0 == memberID })
            section.groupChats[index].writableMemberIDs.removeAll(where: { $0 == memberID })
            section.groupChats[index].pinnedMessageIDs = section.groupChats[index].pinnedMessageIDs.filter { messageID in
                section.groupChats[index].messages.contains(where: { $0.id == messageID })
            }
        }

        for index in section.sectionTasks.indices {
            section.sectionTasks[index].assigneeIDs.removeAll(where: { $0 == memberID })
            section.sectionTasks[index].doneMemberIDs.removeAll(where: { $0 == memberID })
            section.sectionTasks[index].verifiedMemberIDs.removeAll(where: { $0 == memberID })
        }

        onSave()
    }

    private func addMemberByAccountID() {
        let cleanedID = manualMemberAccountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else { return }

        let profiles = decodeRegisteredProfiles(from: registeredProfilesRaw)
        guard let profile = profiles.first(where: { $0.accountID == cleanedID }) else {
            manualAddStatusMessage = "No account found with ID \(cleanedID)."
            return
        }

        if let existingIndex = section.members.firstIndex(where: { $0.accountID == cleanedID || $0.phoneNumber == profile.phoneNumber }) {
            section.members[existingIndex].name = profile.name
            section.members[existingIndex].phoneNumber = profile.phoneNumber
            section.members[existingIndex].accountID = profile.accountID
            manualAddStatusMessage = "\(abbreviatedDisplayName(profile.name)) is already in this section. Info was refreshed."
        } else {
            section.members.append(
                SectionMember(
                    accountID: profile.accountID,
                    name: profile.name,
                    phoneNumber: profile.phoneNumber,
                    role: profile.role == .manager ? .foreman : .journeyman,
                    isOnSite: false
                )
            )
            manualAddStatusMessage = "Added \(abbreviatedDisplayName(profile.name)) to this section."
        }

        manualMemberAccountID = ""
        onSave()
    }

    private func saveSectionIdentity() {
        let cleanedName = sectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = normalizeCodeWord(codeWordDraft)
        guard !cleanedName.isEmpty, !normalizedCode.isEmpty else { return }

        let existingSections = decodeSections(from: managerSectionsRaw)
        let codeInUse = existingSections.contains { $0.id != section.id && $0.codeWord == normalizedCode }
        guard !codeInUse else {
            sectionIdentityStatusMessage = localized("That code word is already being used by another section.", language)
            return
        }

        section.name = cleanedName
        section.codeWord = normalizedCode
        sectionNameDraft = cleanedName
        codeWordDraft = normalizedCode
        sectionIdentityStatusMessage = localized("Crew details saved.", language)
        onSave()
    }

    private func addMemberFromParent(_ member: SectionMember) {
        guard !section.members.contains(where: { $0.phoneNumber == member.phoneNumber }) else { return }
        section.members.append(member)
        manualAddStatusMessage = "\(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw)) \(localized("added from parent section.", language))"
        onSave()
    }
}

struct ManagerSectionTaskDetailView: View {
    @Binding var task: SectionTask
    let members: [SectionMember]
    let onSave: () -> Void
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""

    @State private var taskTitleDraft = ""
    @State private var taskDescriptionDraft = ""
    @State private var managerNotesDraft = ""
    @State private var showTaskPhotoPicker = false

    private var assignedMembers: [SectionMember] {
        members.filter { task.assigneeIDs.contains($0.id) }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private func completionLabel(for member: SectionMember) -> String {
        if task.requiresAcknowledgement && task.verifiedMemberIDs.contains(member.id) {
            return localized("Verified", language)
        }
        if task.doneMemberIDs.contains(member.id) {
            return task.requiresAcknowledgement ? localized("To Verify", language) : localized("Done", language)
        }
        return localized("Assigned", language)
    }

    var body: some View {
        List {
            Section(localized("Task", language)) {
                HStack {
                    TextField(localized("Task title", language), text: $taskTitleDraft)
                        .font(.headline)
                    Spacer()
                    Text(task.priority.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(task.priority.color.opacity(0.18), in: Capsule())
                }
                Text(localized("Due", language) + " \(task.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !task.siteName.isEmpty {
                    Text("\(localized("Site", language)): \(task.siteName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !task.locationDetails.isEmpty {
                    Text("\(localized("Location", language)): \(task.locationDetails)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if task.requiresAcknowledgement {
                    Label(localized("Requires acknowledgement", language), systemImage: "checkmark.message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Description", language)) {
                TextEditor(text: $taskDescriptionDraft)
                    .frame(minHeight: 100)
            }

            if !task.checklistItems.isEmpty {
                Section(localized("Checklist Items", language)) {
                    ForEach(task.checklistItems) { item in
                        Label(item.title, systemImage: "checklist")
                    }
                }
            }

            if !task.attachments.isEmpty {
                Section(localized("Attachments", language)) {
                    ForEach(task.attachments) { attachment in
                        TaskAttachmentPreviewRow(attachment: attachment)
                    }
                }
            }

            Section(localized("Task Photos", language)) {
                Button(localized("Attach Photo", language)) {
                    showTaskPhotoPicker = true
                }

                Text(localized("Attached task photos are visible to all crew members assigned to this task.", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(localized("Crew Lead Notes", language)) {
                TextEditor(text: $managerNotesDraft)
                    .frame(minHeight: 120)

                Button(localized("Save Task Updates", language)) {
                    task.title = taskTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    task.descriptionText = taskDescriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    task.managerNotes = managerNotesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section(localized("Completion Status", language)) {
                if assignedMembers.isEmpty {
                    Text(localized("No members assigned to this task.", language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(assignedMembers) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                Text(member.roleDisplayTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if task.requiresAcknowledgement && task.doneMemberIDs.contains(member.id) && !task.verifiedMemberIDs.contains(member.id) {
                                Button(localized("Verify", language)) {
                                    task.verifiedMemberIDs.append(member.id)
                                    onSave()
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Label(completionLabel(for: member), systemImage: task.verifiedMemberIDs.contains(member.id) ? "checkmark.seal.fill" : (task.doneMemberIDs.contains(member.id) ? "checkmark.circle.fill" : "circle"))
                                    .foregroundStyle(task.doneMemberIDs.contains(member.id) ? .green : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(localized("Task Details", language))
        .onAppear {
            taskTitleDraft = task.title
            taskDescriptionDraft = task.descriptionText
            managerNotesDraft = task.managerNotes
        }
        .sheet(isPresented: $showTaskPhotoPicker) {
            TaskPhotoPicker { attachment in
                task.attachments.append(attachment)
                onSave()
            }
        }
    }
}

struct SectionGroupChatDetailView: View {
    @Binding var chat: SectionGroupChat
    let members: [SectionMember]
    let onSave: () -> Void
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""

    @State private var newMessageText = ""
    @State private var showSettings = false
    @State private var showMediaPicker = false
    @State private var showMediaTypeDialog = false
    @State private var selectedMediaType: ChatMessageType = .photo

    private var pinnedMessages: [GroupChatMessage] {
        chat.messages.filter { chat.pinnedMessageIDs.contains($0.id) }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    var body: some View {
        VStack(spacing: 0) {
            if !pinnedMessages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pinnedMessages) { message in
                            Text("📌 \(messagePreview(message))")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.yellow.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color(uiColor: .systemBackground))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if chat.messages.isEmpty {
                            Text("No messages yet.")
                                .textCase(nil)
                                .foregroundStyle(.secondary)
                                .padding(.top, 30)
                        } else {
                            ForEach(chat.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .onAppear {
                    scrollToBottom(using: proxy)
                }
                .onChange(of: chat.messages.count) { _ in
                    scrollToBottom(using: proxy)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showMediaTypeDialog = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.arcAccentOrange)
                }

                TextField(localized("Type a message", language), text: $newMessageText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    .textInputAutocapitalization(.sentences)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .foregroundStyle(Color.arcAccentOrange)
                .disabled(newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(uiColor: .systemBackground))
        }
        .navigationTitle(chat.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                GroupChatSettingsView(
                    chat: $chat,
                    members: members,
                    onSave: onSave,
                    onDone: { showSettings = false }
                )
            }
            .navigationViewStyle(.stack)
        }
        .sheet(isPresented: $showMediaPicker) {
            MediaPicker(mediaType: selectedMediaType) { type, label in
                sendMediaMessage(type: type, label: label)
            }
        }
        .confirmationDialog(localized("Send Media", language), isPresented: $showMediaTypeDialog) {
            Button(localized("Photo", language)) {
                selectedMediaType = .photo
                showMediaPicker = true
            }
            Button(localized("Video", language)) {
                selectedMediaType = .video
                showMediaPicker = true
            }
            Button(localized("Cancel", language), role: .cancel) { }
        }
    }

    private func sendMessage() {
        let cleanedText = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return }

        chat.messages.append(
            GroupChatMessage(
                sender: "Crew Lead",
                text: cleanedText,
                time: shortTimeString(),
                messageType: .text
            )
        )
        onSave()
        newMessageText = ""
    }

    @ViewBuilder
    private func messageBubble(_ message: GroupChatMessage) -> some View {
        let isCurrentUser = message.sender == "Crew Lead"
        if message.messageType == .text {
            HStack {
                if isCurrentUser {
                    Spacer(minLength: 40)
                }

                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    Text(displaySenderName(message.sender))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(messagePreview(message))
                        .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            isCurrentUser ? Color.blue : Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    Text(message.time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button(chat.pinnedMessageIDs.contains(message.id) ? "Unpin Message" : "Pin Message") {
                        togglePinnedMessage(message.id)
                    }
                    Menu("React") {
                        ForEach(ChatReaction.allCases) { reaction in
                            Button(reaction.rawValue) {
                                toggleReaction(messageID: message.id, emoji: reaction.rawValue)
                            }
                        }
                    }
                }
                if !message.reactions.isEmpty {
                    reactionSummaryView(message)
                }

                if !isCurrentUser {
                    Spacer(minLength: 40)
                }
            }
        } else {
            VStack(alignment: .center, spacing: 6) {
                Text(displaySenderName(message.sender))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 230, height: 140)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: message.messageType == .photo ? "photo" : "video")
                                .font(.system(size: 28))
                            Text(message.attachmentLabel ?? (message.messageType == .photo ? "Photo" : "Video"))
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                        .foregroundStyle(.primary)
                    }
                Text(message.time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contextMenu {
                Button(chat.pinnedMessageIDs.contains(message.id) ? "Unpin Message" : "Pin Message") {
                    togglePinnedMessage(message.id)
                }
                Menu("React") {
                    ForEach(ChatReaction.allCases) { reaction in
                        Button(reaction.rawValue) {
                            toggleReaction(messageID: message.id, emoji: reaction.rawValue)
                        }
                    }
                }
            }
            if !message.reactions.isEmpty {
                reactionSummaryView(message)
            }
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard let last = chat.messages.last else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func togglePinnedMessage(_ messageID: UUID) {
        if let index = chat.pinnedMessageIDs.firstIndex(of: messageID) {
            chat.pinnedMessageIDs.remove(at: index)
        } else {
            chat.pinnedMessageIDs.append(messageID)
        }
        onSave()
    }

    private func toggleReaction(messageID: UUID, emoji: String) {
        guard let index = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
        if let reactionIndex = chat.messages[index].reactions.firstIndex(where: { $0.emoji == emoji && $0.by == "Crew Lead" }) {
            chat.messages[index].reactions.remove(at: reactionIndex)
        } else {
            chat.messages[index].reactions.append(
                MessageReaction(emoji: emoji, by: "Crew Lead")
            )
        }
        onSave()
    }

    private func sendMediaMessage(type: ChatMessageType, label: String) {
        chat.messages.append(
            GroupChatMessage(
                sender: "Crew Lead",
                text: "",
                time: shortTimeString(),
                messageType: type,
                attachmentLabel: label
            )
        )
        onSave()
    }

    private func messagePreview(_ message: GroupChatMessage) -> String {
        switch message.messageType {
        case .text:
            return message.text
        case .photo:
            return "📷 \(message.attachmentLabel ?? "Photo")"
        case .video:
            return "🎥 \(message.attachmentLabel ?? "Video")"
        }
    }

    private func displaySenderName(_ sender: String) -> String {
        guard sender != "Crew Lead" else { return sender }
        guard let member = members.first(where: {
            $0.name == sender || abbreviatedDisplayName($0.name) == sender
        }) else {
            return sender
        }
        return managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw)
    }

    @ViewBuilder
    private func reactionSummaryView(_ message: GroupChatMessage) -> some View {
        let grouped = Dictionary(grouping: message.reactions, by: { $0.emoji })
        HStack(spacing: 6) {
            ForEach(grouped.keys.sorted(), id: \.self) { emoji in
                Text("\(emoji) \(grouped[emoji]?.count ?? 0)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .tertiarySystemBackground), in: Capsule())
            }
        }
    }
}

struct GroupChatSettingsView: View {
    @Binding var chat: SectionGroupChat
    let members: [SectionMember]
    let onSave: () -> Void
    let onDone: () -> Void
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""
    @State private var draftChat: SectionGroupChat

    init(
        chat: Binding<SectionGroupChat>,
        members: [SectionMember],
        onSave: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self._chat = chat
        self.members = members
        self.onSave = onSave
        self.onDone = onDone
        _draftChat = State(initialValue: chat.wrappedValue)
    }

    private var participantMembers: [SectionMember] {
        if draftChat.participantMemberIDs.isEmpty { return members }
        return members.filter { draftChat.participantMemberIDs.contains($0.id) }
    }

    private var pinnedMessages: [GroupChatMessage] {
        draftChat.messages.filter { draftChat.pinnedMessageIDs.contains($0.id) }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    var body: some View {
        Form {
            Section(localized("Notifications", language)) {
                Picker(localized("Alert Type", language), selection: $draftChat.notificationSetting) {
                    ForEach(ChatNotificationSetting.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section(localized("Pinned Messages", language)) {
                if pinnedMessages.isEmpty {
                    Text("No messages to pin yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pinnedMessages) { message in
                        Button {
                            togglePinned(message.id)
                        } label: {
                            HStack {
                                Text(messageRowText(message))
                                    .lineLimit(1)
                                Spacer()
                                if draftChat.pinnedMessageIDs.contains(message.id) {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(localized("Members", language)) {
                if participantMembers.isEmpty {
                    Text("No members selected for this chat.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(participantMembers) { member in
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw))
                                Text(member.roleDisplayTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Toggle(
                                isOn: Binding(
                                    get: { draftChat.writableMemberIDs.contains(member.id) },
                                    set: { isWritable in
                                        setWriteAccess(for: member.id, isWritable: isWritable)
                                    }
                                )
                            ) {
                                Text(draftChat.writableMemberIDs.contains(member.id) ? localized("Can write in chat", language) : localized("Read only", language))
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(localized("Chat Details", language))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(localized("Done", language)) {
                    onDone()
                    DispatchQueue.main.async {
                        persistDraftChanges()
                    }
                }
            }
        }
    }

    private func togglePinned(_ messageID: UUID) {
        if let index = draftChat.pinnedMessageIDs.firstIndex(of: messageID) {
            draftChat.pinnedMessageIDs.remove(at: index)
        } else {
            draftChat.pinnedMessageIDs.append(messageID)
        }
    }

    private func messageRowText(_ message: GroupChatMessage) -> String {
        let senderName: String
        if let member = members.first(where: {
            $0.name == message.sender || abbreviatedDisplayName($0.name) == message.sender
        }) {
            senderName = managerVisibleName(member, nicknamesRaw: managerCrewNicknamesRaw)
        } else {
            senderName = message.sender
        }

        switch message.messageType {
        case .text:
            return "\(senderName): \(message.text)"
        case .photo:
            return "\(senderName): 📷 \(message.attachmentLabel ?? "Photo")"
        case .video:
            return "\(senderName): 🎥 \(message.attachmentLabel ?? "Video")"
        }
    }

    private func setWriteAccess(for memberID: UUID, isWritable: Bool) {
        if isWritable {
            if !draftChat.writableMemberIDs.contains(memberID) {
                draftChat.writableMemberIDs.append(memberID)
            }
        } else {
            draftChat.writableMemberIDs.removeAll(where: { $0 == memberID })
        }
    }

    private func persistDraftChanges() {
        chat = draftChat
        onSave()
    }
}

struct ManagerMemberTodoDetailView: View {
    @Binding var todo: MemberTodo
    let onSave: () -> Void
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue

    @State private var titleDraft = ""
    @State private var dueDateDraft = Date()
    @State private var priorityDraft: TaskPriority = .medium
    @State private var descriptionDraft = ""
    @State private var siteNameDraft = ""
    @State private var locationDraft = ""
    @State private var checklistItemTitleDraft = ""
    @State private var checklistDraft: [TaskChecklistItem] = []
    @State private var attachmentsDraft: [TaskAttachment] = []
    @State private var requiresAcknowledgementDraft = false
    @State private var notesDraft = ""
    @State private var doneDraft = false
    @State private var completedDraft = false
    @State private var showAttachmentTypeDialog = false
    @State private var showMediaPicker = false
    @State private var showPDFImporter = false
    @State private var selectedAttachmentType: TaskAttachmentType = .photo

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    var body: some View {
        List {
            Section(localized("To-Do Details", language)) {
                TextField(localized("To-do title", language), text: $titleDraft)
                    .textInputAutocapitalization(.sentences)

                DatePicker(
                    localized("Due Date", language),
                    selection: $dueDateDraft,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Picker(localized("Priority", language), selection: $priorityDraft) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }

                Toggle(localized("Requires acknowledgement", language), isOn: $requiresAcknowledgementDraft)

                if requiresAcknowledgementDraft {
                    Toggle(localized("Done", language), isOn: $doneDraft)
                    Toggle(localized("Completed", language), isOn: $completedDraft)
                } else {
                    Toggle(localized("Completed", language), isOn: $completedDraft)
                }

                TextField(localized("Site", language), text: $siteNameDraft)
                    .textInputAutocapitalization(.words)

                TextField(localized("Location (optional)", language), text: $locationDraft)
                    .textInputAutocapitalization(.words)
            }

            Section(localized("Description", language)) {
                TextEditor(text: $descriptionDraft)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if descriptionDraft.isEmpty {
                            Text(localized("Description (use keyboard or dictation)", language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 6)
                        }
                    }
            }

            Section(localized("Checklist Items", language)) {
                HStack {
                    TextField(localized("Checklist item", language), text: $checklistItemTitleDraft)
                        .textInputAutocapitalization(.sentences)

                    Button(localized("Add", language)) {
                        addChecklistItem()
                    }
                    .disabled(checklistItemTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if checklistDraft.isEmpty {
                    Text(localized("No checklist items yet.", language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(checklistDraft) { item in
                        HStack {
                            Label(item.title, systemImage: "checklist")
                            Spacer()
                            Button(localized("Delete", language), role: .destructive) {
                                checklistDraft.removeAll(where: { $0.id == item.id })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section(localized("Attachments", language)) {
                Button(localized("Add Attachment", language)) {
                    showAttachmentTypeDialog = true
                }

                if attachmentsDraft.isEmpty {
                    Text(localized("No attachments yet.", language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachmentsDraft) { attachment in
                        HStack {
                            Label(attachment.label, systemImage: attachment.type.systemImage)
                            Spacer()
                            Button(localized("Delete", language), role: .destructive) {
                                attachmentsDraft.removeAll(where: { $0.id == attachment.id })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section(localized("Crew Lead Notes", language)) {
                TextEditor(text: $notesDraft)
                    .frame(minHeight: 120)
            }

            Section {
                Button(localized("Save To-Do Updates", language)) {
                    todo.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    todo.descriptionText = descriptionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    todo.dueDate = dueDateDraft
                    todo.priority = priorityDraft
                    todo.siteName = siteNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    todo.locationDetails = locationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    todo.checklistItems = checklistDraft
                    todo.attachments = attachmentsDraft
                    todo.requiresAcknowledgement = requiresAcknowledgementDraft
                    todo.managerNotes = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    todo.isMarkedDone = requiresAcknowledgementDraft ? (doneDraft || completedDraft) : completedDraft
                    todo.isCompleted = requiresAcknowledgementDraft ? completedDraft : completedDraft
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(localized("To-Do Details", language))
        .onAppear {
            titleDraft = todo.title
            descriptionDraft = todo.descriptionText
            dueDateDraft = todo.dueDate
            priorityDraft = todo.priority
            siteNameDraft = todo.siteName
            locationDraft = todo.locationDetails
            checklistDraft = todo.checklistItems
            attachmentsDraft = todo.attachments
            requiresAcknowledgementDraft = todo.requiresAcknowledgement
            notesDraft = todo.managerNotes
            doneDraft = todo.isMarkedDone
            completedDraft = todo.isCompleted
        }
        .onChange(of: completedDraft) { newValue in
            if requiresAcknowledgementDraft {
                if newValue {
                    doneDraft = true
                } else {
                    doneDraft = false
                }
            }
        }
        .onChange(of: requiresAcknowledgementDraft) { newValue in
            if !newValue {
                doneDraft = completedDraft
            } else if completedDraft {
                doneDraft = true
            }
        }
        .sheet(isPresented: $showMediaPicker) {
            MediaPicker(mediaType: selectedAttachmentType == .video ? .video : .photo) { type, label in
                let attachmentType: TaskAttachmentType = type == .video ? .video : .photo
                attachmentsDraft.append(TaskAttachment(type: attachmentType, label: label))
            }
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            attachmentsDraft.append(TaskAttachment(type: .pdf, label: url.lastPathComponent))
        }
        .confirmationDialog(localized("Add Attachment", language), isPresented: $showAttachmentTypeDialog) {
            Button(localized("Photo", language)) {
                selectedAttachmentType = .photo
                showMediaPicker = true
            }
            Button(localized("Video", language)) {
                selectedAttachmentType = .video
                showMediaPicker = true
            }
            Button("PDF") {
                showPDFImporter = true
            }
            Button(localized("Cancel", language), role: .cancel) { }
        }
    }

    private func addChecklistItem() {
        let cleanedTitle = checklistItemTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        checklistDraft.append(TaskChecklistItem(title: cleanedTitle))
        checklistItemTitleDraft = ""
    }
}

struct MemberDetailView: View {
    @Binding var member: SectionMember
    let sectionTasks: [SectionTask]
    let onSave: () -> Void
    let walkthroughFocusTarget: WalkthroughTargetID?
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""

    @State private var newTodoTitle = ""
    @State private var selectedTodoDate = Date()
    @State private var newTodoPriority: TaskPriority = .medium
    @State private var newTodoDescription = ""
    @State private var newTodoSiteName = ""
    @State private var newTodoLocation = ""
    @State private var newTodoManagerNotes = ""
    @State private var newTodoChecklistItemTitle = ""
    @State private var newTodoChecklistItems: [TaskChecklistItem] = []
    @State private var newTodoAttachments: [TaskAttachment] = []
    @State private var newTodoRequiresAcknowledgement = false
    @State private var showTodoAttachmentTypeDialog = false
    @State private var showTodoMediaPicker = false
    @State private var showTodoPDFImporter = false
    @State private var selectedTodoAttachmentType: TaskAttachmentType = .photo
    @State private var todoViewMode: TaskTimelineView = .week
    @State private var isAddTodoExpanded = false
    @State private var selectedTodoViewDate = Date()
    @State private var selectedTodoWeekAnchor = Date()
    @State private var nicknameDraft = ""

    init(
        member: Binding<SectionMember>,
        sectionTasks: [SectionTask],
        onSave: @escaping () -> Void,
        walkthroughFocusTarget: WalkthroughTargetID? = nil
    ) {
        self._member = member
        self.sectionTasks = sectionTasks
        self.onSave = onSave
        self.walkthroughFocusTarget = walkthroughFocusTarget
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var nicknameKey: String {
        crewNicknameKey(accountID: member.accountID, phoneNumber: member.phoneNumber)
    }

    private var scheduledItems: [ScheduledItem] {
        let personal = member.todos.map {
            ScheduledItem(
                id: $0.id,
                title: $0.title,
                dueDate: $0.dueDate,
                priority: $0.priority,
                isPersonal: true,
                isCompleted: $0.requiresAcknowledgement ? $0.isCompleted : $0.isMarkedDone,
                isAwaitingVerification: $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
            )
        }
        let sectionAssigned = sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .map {
                ScheduledItem(
                    id: $0.id,
                    title: $0.title,
                    dueDate: $0.dueDate,
                    priority: $0.priority,
                    isPersonal: false,
                    isCompleted: $0.requiresAcknowledgement ? $0.verifiedMemberIDs.contains(member.id) : $0.doneMemberIDs.contains(member.id),
                    isAwaitingVerification: $0.requiresAcknowledgement && $0.doneMemberIDs.contains(member.id) && !$0.verifiedMemberIDs.contains(member.id)
                )
            }
        return (personal + sectionAssigned).sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        List {
            Section(localized("Profile", language)) {
                Text(member.name)
                    .font(.headline)
                Text(abbreviatedDisplayName(member.name))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(localized("Note", language), text: $nicknameDraft)
                    .textInputAutocapitalization(.words)

                Button(localized("Save Note", language)) {
                    saveNickname()
                }
                .disabled(
                    nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines) ==
                    decodeManagerCrewNicknames(from: managerCrewNicknamesRaw)[nicknameKey, default: ""]
                )
            }

            Section(localized("Role & Status", language)) {
                Picker(localized("Role", language), selection: $member.role) {
                    ForEach(MemberRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .onChange(of: member.role) { _ in
                    if member.role != .other {
                        member.customRoleTitle = ""
                    }
                    onSave()
                }

                if member.role == .other {
                    TextField(localized("Custom Role", language), text: $member.customRoleTitle)
                        .textInputAutocapitalization(.words)
                        .onChange(of: member.customRoleTitle) { _ in
                            onSave()
                        }
                }

                Toggle(localized("On Site", language), isOn: $member.isOnSite)
                    .onChange(of: member.isOnSite) { _ in
                        onSave()
                    }
            }

            Section(localized("Today's Time Clock", language)) {
                HStack {
                    Text(localized("Clocked In", language))
                    Spacer()
                    if let clockInTime = member.clockInTime, isToday(clockInTime) {
                        Text(clockInTime, style: .time)
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(localized("Clocked Out", language))
                    Spacer()
                    if let clockOutTime = member.clockOutTime, isToday(clockOutTime) {
                        Text(clockOutTime, style: .time)
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .walkthroughTarget(walkthroughFocusTarget == .memberTimeClock ? .memberTimeClock : nil)

            Section(localized("Scheduled To-Dos", language)) {
                if scheduledItems.isEmpty {
                    Text(localized("No to-dos assigned yet.", language))
                        .foregroundStyle(.secondary)
                }

                Picker(localized("To-Do View", language), selection: $todoViewMode) {
                    ForEach(TaskTimelineView.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if todoViewMode == .calendar {
                    EventCalendarView(
                        selectedDate: $selectedTodoViewDate,
                        highlightedDates: scheduledItems.map(\.dueDate),
                        language: language
                    )

                    let dailyItems = scheduledItemsForDate(selectedTodoViewDate)
                    if dailyItems.isEmpty {
                        Text(localized("No to-dos on this date.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dailyItems) { item in
                            if item.isPersonal {
                                if let todoBinding = todoBinding(for: item.id) {
                                    NavigationLink {
                                        ManagerMemberTodoDetailView(todo: todoBinding, onSave: onSave)
                                    } label: {
                                        scheduledItemRow(item)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(localized("Delete", language), role: .destructive) {
                                            deleteTodo(item.id)
                                        }
                                    }
                                } else {
                                    scheduledItemRow(item)
                                        .swipeActions(edge: .trailing) {
                                            Button(localized("Delete", language), role: .destructive) {
                                                deleteTodo(item.id)
                                            }
                                        }
                                }
                            } else {
                                scheduledItemRow(item)
                            }
                        }
                    }
                } else {
                    DatePicker(
                        localized("Week Of", language),
                        selection: $selectedTodoWeekAnchor,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)

                    let weeklyBuckets = scheduledItemsForSelectedWeek()
                    if weeklyBuckets.isEmpty {
                        Text(localized("No to-dos in this week.", language))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(weeklyBuckets, id: \.date) { bucket in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(weekHeaderString(for: bucket.date))
                                    .font(.subheadline.weight(.semibold))
                                ForEach(bucket.items) { item in
                                    if item.isPersonal {
                                        if let todoBinding = todoBinding(for: item.id) {
                                            NavigationLink {
                                                ManagerMemberTodoDetailView(todo: todoBinding, onSave: onSave)
                                            } label: {
                                                scheduledItemRow(item)
                                            }
                                            .swipeActions(edge: .trailing) {
                                                Button(localized("Delete", language), role: .destructive) {
                                                    deleteTodo(item.id)
                                                }
                                            }
                                        } else {
                                            scheduledItemRow(item)
                                                .swipeActions(edge: .trailing) {
                                                    Button(localized("Delete", language), role: .destructive) {
                                                        deleteTodo(item.id)
                                                    }
                                                }
                                        }
                                    } else {
                                        scheduledItemRow(item)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                DisclosureGroup(isExpanded: $isAddTodoExpanded) {
                    if todoViewMode == .calendar {
                        HStack {
                            Text(localized("Due Date", language))
                            Spacer()
                            Text(selectedTodoViewDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        }
                        DatePicker(
                            localized("Due Time", language),
                            selection: $selectedTodoDate,
                            displayedComponents: .hourAndMinute
                        )
                    } else {
                        DatePicker(
                            localized("Due Date", language),
                            selection: $selectedTodoDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    TextField(localized("To-do item", language), text: $newTodoTitle)
                        .textInputAutocapitalization(.sentences)

                    TextEditor(text: $newTodoDescription)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if newTodoDescription.isEmpty {
                                Text(localized("Description (use keyboard or dictation)", language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                            }
                        }

                    Picker(localized("Priority", language), selection: $newTodoPriority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }

                    TextField(localized("Site", language), text: $newTodoSiteName)
                        .textInputAutocapitalization(.words)

                    TextField(localized("Location (optional)", language), text: $newTodoLocation)
                        .textInputAutocapitalization(.words)

                    HStack {
                        TextField(localized("Checklist item", language), text: $newTodoChecklistItemTitle)
                            .textInputAutocapitalization(.sentences)

                        Button(localized("Add", language)) {
                            addTodoChecklistItem()
                        }
                        .disabled(newTodoChecklistItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !newTodoChecklistItems.isEmpty {
                        ForEach(newTodoChecklistItems) { item in
                            HStack {
                                Text(item.title)
                                Spacer()
                                Button(localized("Delete", language), role: .destructive) {
                                    newTodoChecklistItems.removeAll(where: { $0.id == item.id })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(localized("Add Attachment", language)) {
                        showTodoAttachmentTypeDialog = true
                    }

                    if !newTodoAttachments.isEmpty {
                        ForEach(newTodoAttachments) { attachment in
                            HStack {
                                Label(attachment.label, systemImage: attachment.type.systemImage)
                                Spacer()
                                Button(localized("Delete", language), role: .destructive) {
                                    newTodoAttachments.removeAll(where: { $0.id == attachment.id })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    TextEditor(text: $newTodoManagerNotes)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if newTodoManagerNotes.isEmpty {
                                Text(localized("Crew Lead notes (optional)", language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                            }
                        }

                    Toggle(localized("Requires acknowledgement", language), isOn: $newTodoRequiresAcknowledgement)

                    Button(localized("Add To-Do", language)) {
                        addTodo()
                    }
                    .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } label: {
                    Label(localized("Add To-Do", language), systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(member.name)
        .onAppear {
            nicknameDraft = decodeManagerCrewNicknames(from: managerCrewNicknamesRaw)[nicknameKey, default: ""]
        }
        .onChange(of: selectedTodoViewDate) { newValue in
            if todoViewMode == .calendar {
                selectedTodoDate = merged(date: newValue, withTimeFrom: selectedTodoDate)
            }
        }
        .sheet(isPresented: $showTodoMediaPicker) {
            MediaPicker(mediaType: selectedTodoAttachmentType == .video ? .video : .photo) { type, label in
                let attachmentType: TaskAttachmentType = type == .video ? .video : .photo
                newTodoAttachments.append(TaskAttachment(type: attachmentType, label: label))
            }
        }
        .fileImporter(isPresented: $showTodoPDFImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            newTodoAttachments.append(TaskAttachment(type: .pdf, label: url.lastPathComponent))
        }
        .confirmationDialog(localized("Add Attachment", language), isPresented: $showTodoAttachmentTypeDialog) {
            Button(localized("Photo", language)) {
                selectedTodoAttachmentType = .photo
                showTodoMediaPicker = true
            }
            Button(localized("Video", language)) {
                selectedTodoAttachmentType = .video
                showTodoMediaPicker = true
            }
            Button("PDF") {
                showTodoPDFImporter = true
            }
            Button(localized("Cancel", language), role: .cancel) { }
        }
    }

    private func saveNickname() {
        var nicknames = decodeManagerCrewNicknames(from: managerCrewNicknamesRaw)
        let cleanedNickname = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedNickname.isEmpty {
            nicknames.removeValue(forKey: nicknameKey)
        } else {
            nicknames[nicknameKey] = cleanedNickname
        }
        managerCrewNicknamesRaw = encodeManagerCrewNicknames(nicknames)
    }

    private func addTodo() {
        let cleanedTitle = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        let dueDate = todoViewMode == .calendar
            ? merged(date: selectedTodoViewDate, withTimeFrom: selectedTodoDate)
            : selectedTodoDate

        member.todos.append(
            MemberTodo(
                title: cleanedTitle,
                descriptionText: newTodoDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: dueDate,
                priority: newTodoPriority,
                siteName: newTodoSiteName.trimmingCharacters(in: .whitespacesAndNewlines),
                locationDetails: newTodoLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                checklistItems: newTodoChecklistItems,
                attachments: newTodoAttachments,
                requiresAcknowledgement: newTodoRequiresAcknowledgement,
                managerNotes: newTodoManagerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        newTodoTitle = ""
        newTodoDescription = ""
        newTodoPriority = .medium
        newTodoLocation = ""
        newTodoManagerNotes = ""
        newTodoChecklistItemTitle = ""
        newTodoChecklistItems = []
        newTodoAttachments = []
        newTodoRequiresAcknowledgement = false
        isAddTodoExpanded = false
        onSave()
    }

    private func addTodoChecklistItem() {
        let cleanedTitle = newTodoChecklistItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        newTodoChecklistItems.append(TaskChecklistItem(title: cleanedTitle))
        newTodoChecklistItemTitle = ""
    }

    private func deleteTodo(_ id: UUID) {
        member.todos.removeAll(where: { $0.id == id })
        onSave()
    }

    private func scheduledItemsForDate(_ date: Date) -> [ScheduledItem] {
        scheduledItems
            .filter { Calendar.current.isDate($0.dueDate, inSameDayAs: date) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func scheduledItemsForSelectedWeek() -> [(date: Date, items: [ScheduledItem])] {
        let start = startOfWeek(for: selectedTodoWeekAnchor)
        return (0..<7).compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: start) else { return nil }
            let dayItems = scheduledItemsForDate(day)
            return dayItems.isEmpty ? nil : (day, dayItems)
        }
    }

    @ViewBuilder
    private func scheduledItemRow(_ item: ScheduledItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.title)
                    .font(.headline)
                Spacer()
                Text(item.priority.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.priority.color.opacity(0.18), in: Capsule())
            }
            HStack {
                Text(item.dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if item.isAwaitingVerification {
                    Label(localized("To Verify", language), systemImage: "clock.badge.checkmark.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if item.isCompleted {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Pending", systemImage: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func weekHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func merged(date: Date, withTimeFrom timeSource: Date) -> Date {
        let calendar = Calendar.current
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeSource)
        dayComponents.hour = timeComponents.hour
        dayComponents.minute = timeComponents.minute
        return calendar.date(from: dayComponents) ?? date
    }

    private func todoBinding(for id: UUID) -> Binding<MemberTodo>? {
        guard let index = member.todos.firstIndex(where: { $0.id == id }) else { return nil }
        return $member.todos[index]
    }

    private struct ScheduledItem: Identifiable {
        let id: UUID
        let title: String
        let dueDate: Date
        let priority: TaskPriority
        let isPersonal: Bool
        let isCompleted: Bool
        let isAwaitingVerification: Bool
    }
}
private struct ManagerViewsPreviewContainer: View {
    @State private var bluetoothManager = BluetoothManager()
    private let previewDefaults = UserDefaults(suiteName: "ManagerViewsPreviewDefaults") ?? .standard

    var body: some View {
        ManagerHomeView(
            profileName: defaultManagerDemoProfile().name,
            onSignOut: { }
        )
        .environment(bluetoothManager)
        .defaultAppStorage(previewDefaults)
        .onAppear {
            previewDefaults.removePersistentDomain(forName: "ManagerViewsPreviewDefaults")
        }
    }
}

#Preview {
    ManagerViewsPreviewContainer()
}
