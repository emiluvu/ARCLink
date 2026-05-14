//
//  SectionParticipantViews.swift
//  test
//

import SwiftUI

struct ManagerAssignedSectionDashboardView: View {
    private struct SnapshotMetric: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let systemImage: String
        let tint: Color
    }

    let profileName: String
    let profileAccountID: String
    let profilePhoneNumber: String
    let sectionCode: String

    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("workerPrivateTaskNotesJSON") private var workerPrivateTaskNotesRaw = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue

    private var currentSection: ManagerSection? {
        decodeSections(from: managerSectionsRaw).first(where: { $0.codeWord == sectionCode })
    }

    private var currentMember: SectionMember? {
        guard let section = currentSection else { return nil }
        return section.members.first(where: {
            (!profileAccountID.isEmpty && $0.accountID == profileAccountID) ||
            $0.phoneNumber == profilePhoneNumber
        })
    }

    private var assignedSectionTasks: [SectionTask] {
        guard let section = currentSection, let member = currentMember else { return [] }
        return section.sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var personalTodos: [MemberTodo] {
        currentMember?.todos.sorted { $0.dueDate < $1.dueDate } ?? []
    }

    private var availableChats: [SectionGroupChat] {
        guard let section = currentSection, let member = currentMember else { return [] }
        return section.groupChats.filter {
            $0.participantMemberIDs.isEmpty || $0.participantMemberIDs.contains(member.id)
        }
    }

    private var todayClockIn: Date? {
        guard let clockIn = currentMember?.clockInTime, Calendar.current.isDateInToday(clockIn) else { return nil }
        return clockIn
    }

    private var todayClockOut: Date? {
        guard let clockOut = currentMember?.clockOutTime, Calendar.current.isDateInToday(clockOut) else { return nil }
        return clockOut
    }

    private var isClockedInNow: Bool {
        todayClockIn != nil && todayClockOut == nil
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var snapshotMetrics: [SnapshotMetric] {
        guard let section = currentSection else { return [] }
        return [
            SnapshotMetric(
                title: localized("Members", language),
                value: "\(section.members.count)",
                systemImage: "person.3.fill",
                tint: .blue
            ),
            SnapshotMetric(
                title: localized("On Site", language),
                value: "\(section.members.filter(\.isOnSite).count)",
                systemImage: "checkmark.seal.fill",
                tint: .green
            ),
            SnapshotMetric(
                title: localized("Due Today", language),
                value: "\(tasksDueTodayCount)",
                systemImage: "calendar",
                tint: .orange
            ),
            SnapshotMetric(
                title: localized("To Verify", language),
                value: "\(itemsAwaitingVerificationCount)",
                systemImage: "clock.badge.checkmark.fill",
                tint: .red
            )
        ]
    }

    private var tasksDueTodayCount: Int {
        guard let section = currentSection else { return 0 }
        let calendar = Calendar.current
        let sectionTasksDueToday = section.sectionTasks.filter { calendar.isDateInToday($0.dueDate) }.count
        let personalTodosDueToday = section.members.flatMap(\.todos).filter { calendar.isDateInToday($0.dueDate) }.count
        return sectionTasksDueToday + personalTodosDueToday
    }

    private var itemsAwaitingVerificationCount: Int {
        guard let section = currentSection else { return 0 }
        let tasksAwaitingVerification = section.sectionTasks.filter { task in
            task.requiresAcknowledgement && task.doneMemberIDs.contains(where: { !task.verifiedMemberIDs.contains($0) })
        }.count
        let todosAwaitingVerification = section.members.flatMap(\.todos).filter {
            $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
        }.count
        return tasksAwaitingVerification + todosAwaitingVerification
    }

    var body: some View {
        List {
            if let section = currentSection {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.title2.weight(.semibold))
                        Text(section.codeWord)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(localized("Section Snapshot", language)) {
                    sectionSnapshotCard(section)
                    memberStatusBoard(section)
                    taskCompletionHeatmap(section)
                }

                if section.featureSettings.timeClockEnabled {
                    Section(localized("Time Clock", language)) {
                        Label(localized("Shift: Day Shift", language), systemImage: "clock.fill")
                        if isClockedInNow {
                            Label(localized("Status: On Site", language), systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(localized("Status: Off Site", language), systemImage: "xmark.seal")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button(localized("Clock In", language)) {
                                clockIn()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isClockedInNow)

                            Button(localized("Clock Out", language)) {
                                clockOut()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!isClockedInNow)
                        }

                        if let clockIn = todayClockIn {
                            Text(localized("Clocked In", language) + ": \(clockIn.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                        if let clockOut = todayClockOut {
                            Text(localized("Clocked Out", language) + ": \(clockOut.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if section.featureSettings.sectionTasksEnabled {
                    Section(localized("Assigned Tasks", language)) {
                        if assignedSectionTasks.isEmpty {
                            Text("No section tasks assigned to you yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(assignedSectionTasks) { task in
                                HStack(alignment: .top, spacing: 12) {
                                    Button {
                                        setTaskCompletion(taskID: task.id, isCompleted: !isTaskMarkedDoneForCurrentMember(task))
                                    } label: {
                                        Image(systemName: isTaskCompletedForCurrentMember(task) ? "checkmark.circle.fill" : (isTaskMarkedDoneForCurrentMember(task) ? "clock.badge.checkmark.fill" : "circle"))
                                            .font(.title3)
                                            .foregroundStyle(isTaskCompletedForCurrentMember(task) ? .green : (isTaskMarkedDoneForCurrentMember(task) ? .orange : .secondary))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)

                                    NavigationLink {
                                        WorkerTaskDetailView(
                                            task: task,
                                            isCompleted: isTaskMarkedDoneForCurrentMember(task),
                                            isVerified: isTaskCompletedForCurrentMember(task),
                                            privateNote: workerPrivateNote(for: task.id),
                                            onToggleCompleted: { isDone in
                                                setTaskCompletion(taskID: task.id, isCompleted: isDone)
                                            },
                                            onSavePrivateNote: { note in
                                                setWorkerPrivateNote(note, for: task.id)
                                            }
                                        )
                                    } label: {
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
                                            Text("Due \(task.dueDate, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    }
                }

                if section.featureSettings.personalTodosEnabled {
                    Section(localized("Personal To-Dos", language)) {
                        if personalTodos.isEmpty {
                            Text("No personal to-dos assigned.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(personalTodos) { todo in
                                HStack(alignment: .top, spacing: 12) {
                                    Button {
                                        setPersonalTodoCompletion(todoID: todo.id, isCompleted: !todo.isCompleted)
                                    } label: {
                                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(todo.isCompleted ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)

                                    NavigationLink {
                                        WorkerPersonalTodoDetailView(
                                            todo: todo,
                                            privateNote: workerPrivateNote(for: todo.id, namespace: "personal"),
                                            onToggleCompleted: { isDone in
                                                setPersonalTodoCompletion(todoID: todo.id, isCompleted: isDone)
                                            },
                                            onSavePrivateNote: { note in
                                                setWorkerPrivateNote(note, for: todo.id, namespace: "personal")
                                            }
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(todo.title)
                                                    .font(.headline)
                                                Spacer()
                                                Text(todo.priority.title)
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(todo.priority.color.opacity(0.18), in: Capsule())
                                            }
                                            Text("Due \(todo.dueDate, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    }
                }

                if section.featureSettings.groupChatsEnabled {
                    Section(localized("Chats", language)) {
                        if availableChats.isEmpty {
                            Text("No chats available for you yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(availableChats) { chat in
                                if let chatBinding = groupChatBinding(for: chat.id), let currentMember {
                                    NavigationLink {
                                        WorkerSectionGroupChatDetailView(
                                            chat: chatBinding,
                                            currentMember: currentMember,
                                            onSave: saveSectionUpdates
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(chat.name)
                                                    .font(.headline)
                                                Spacer()
                                                if !chat.writableMemberIDs.contains(currentMember.id) {
                                                    Text(localized("Read Only", language))
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Text(latestMessagePreview(for: chat))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text(localized("No section found for that code word.", language))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(currentSection?.name ?? localized("Leadership Sections", language))
        .listStyle(.insetGrouped)
    }

    private func isTaskCompletedForCurrentMember(_ task: SectionTask) -> Bool {
        guard let memberID = currentMember?.id else { return false }
        return task.requiresAcknowledgement ? task.verifiedMemberIDs.contains(memberID) : task.doneMemberIDs.contains(memberID)
    }

    private func isTaskMarkedDoneForCurrentMember(_ task: SectionTask) -> Bool {
        guard let memberID = currentMember?.id else { return false }
        return task.doneMemberIDs.contains(memberID)
    }

    @ViewBuilder
    private func sectionSnapshotCard(_ section: ManagerSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Live overview", language))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(snapshotMetrics) { metric in
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
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func memberStatusBoard(_ section: ManagerSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Member Status Board", language))
                .font(.headline)

            if section.members.isEmpty {
                Text(localized("No crews have joined this section yet.", language))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(section.members) { member in
                    HStack(alignment: .center, spacing: 12) {
                        Circle()
                            .fill(statusColor(for: member, in: section))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(member.name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(member.role.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                statusPill(title: memberStatusLabel(for: member, in: section), tint: statusColor(for: member, in: section))
                                Text("\(memberCompletedAssignments(member, in: section))/\(memberAssignedAssignments(member, in: section)) \(localized("done", language).lowercased())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func taskCompletionHeatmap(_ section: ManagerSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Task Completion Heatmap", language))
                .font(.headline)

            if section.members.isEmpty {
                Text(localized("No crews have joined this section yet.", language))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(localized("Member", language))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    ForEach([localized("Tasks", language), localized("To-Dos", language), localized("Total", language)], id: \.self) { column in
                        Text(column)
                            .font(.caption2.weight(.semibold))
                            .frame(width: 44)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(section.members) { member in
                    HStack {
                        Text(member.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        heatmapCell(
                            completed: completedSectionTaskCount(for: member.id, in: section),
                            total: assignedSectionTaskCount(for: member.id, in: section)
                        )
                        heatmapCell(
                            completed: completedPersonalTodoCount(for: member),
                            total: member.todos.count
                        )
                        heatmapCell(
                            completed: memberCompletedAssignments(member, in: section),
                            total: memberAssignedAssignments(member, in: section)
                        )
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func assignedSectionTaskCount(for memberID: UUID, in section: ManagerSection) -> Int {
        section.sectionTasks.filter { $0.assigneeIDs.contains(memberID) }.count
    }

    private func completedSectionTaskCount(for memberID: UUID, in section: ManagerSection) -> Int {
        section.sectionTasks.filter { finalCompletionMemberIDs(for: $0).contains(memberID) }.count
    }

    private func completedPersonalTodoCount(for member: SectionMember) -> Int {
        member.todos.filter { $0.requiresAcknowledgement ? $0.isCompleted : $0.isMarkedDone }.count
    }

    private func memberAssignedAssignments(_ member: SectionMember, in section: ManagerSection) -> Int {
        assignedSectionTaskCount(for: member.id, in: section) + member.todos.count
    }

    private func memberCompletedAssignments(_ member: SectionMember, in section: ManagerSection) -> Int {
        completedSectionTaskCount(for: member.id, in: section) + completedPersonalTodoCount(for: member)
    }

    private func memberStatusLabel(for member: SectionMember, in section: ManagerSection) -> String {
        let assignedTasks = assignedSectionTaskCount(for: member.id, in: section)
        let completedTasks = completedSectionTaskCount(for: member.id, in: section)
        let completedTodos = completedPersonalTodoCount(for: member)
        let hasAwaitingTaskVerification = section.sectionTasks.contains { task in
            task.requiresAcknowledgement &&
            task.assigneeIDs.contains(member.id) &&
            task.doneMemberIDs.contains(member.id) &&
            !task.verifiedMemberIDs.contains(member.id)
        }
        let hasAwaitingPersonalVerification = member.todos.contains {
            $0.requiresAcknowledgement && $0.isMarkedDone && !$0.isCompleted
        }

        if hasAwaitingTaskVerification || hasAwaitingPersonalVerification {
            return localized("Awaiting Verify", language)
        }
        if member.isOnSite {
            if assignedTasks > 0 && completedTasks == assignedTasks && completedTodos == member.todos.count {
                return localized("On Site", language) + " • " + localized("Clear", language)
            }
            return localized("On Site", language)
        }
        return localized("Off Site", language)
    }

    private func statusColor(for member: SectionMember, in section: ManagerSection) -> Color {
        memberStatusLabel(for: member, in: section) == localized("Awaiting Verify", language)
            ? .orange
            : (member.isOnSite ? .green : .secondary)
    }

    private func statusPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private func heatmapCell(completed: Int, total: Int) -> some View {
        let ratio = total == 0 ? 0 : Double(completed) / Double(total)
        let fillColor: Color = total == 0 ? .secondary.opacity(0.14) : completionColor(for: ratio).opacity(0.22)

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fillColor)
                .frame(width: 44, height: 34)
            Text(total == 0 ? "0" : "\(completed)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(total == 0 ? .secondary : completionColor(for: ratio))
        }
        .overlay(alignment: .bottom) {
            if total > 0 {
                Capsule()
                    .fill(completionColor(for: ratio))
                    .frame(width: 30 * ratio, height: 4)
                    .offset(y: -4)
            }
        }
        .accessibilityLabel("\(completed) of \(total)")
    }

    private func completionColor(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.34:
            return .red
        case ..<0.67:
            return .orange
        default:
            return .green
        }
    }

    private func finalCompletionMemberIDs(for task: SectionTask) -> [UUID] {
        task.requiresAcknowledgement ? task.verifiedMemberIDs : task.doneMemberIDs
    }

    private func setTaskCompletion(taskID: UUID, isCompleted: Bool) {
        guard let sectionID = currentSection?.id, let memberID = currentMember?.id else { return }
        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
              let taskIndex = sections[sectionIndex].sectionTasks.firstIndex(where: { $0.id == taskID }) else { return }

        if isCompleted {
            if !sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.contains(memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.append(memberID)
            }
            if !sections[sectionIndex].sectionTasks[taskIndex].requiresAcknowledgement,
               !sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.contains(memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.append(memberID)
            }
        } else {
            sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.removeAll(where: { $0 == memberID })
            sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.removeAll(where: { $0 == memberID })
        }
        managerSectionsRaw = encodeSections(sections)
    }

    private func workerPrivateNote(for taskID: UUID) -> String {
        workerPrivateNote(for: taskID, namespace: "section")
    }

    private func workerPrivateNote(for taskID: UUID, namespace: String) -> String {
        workerPrivateNotesStorage()[privateNoteKey(taskID: taskID, namespace: namespace)] ?? ""
    }

    private func setWorkerPrivateNote(_ note: String, for taskID: UUID) {
        setWorkerPrivateNote(note, for: taskID, namespace: "section")
    }

    private func setWorkerPrivateNote(_ note: String, for taskID: UUID, namespace: String) {
        var notes = workerPrivateNotesStorage()
        notes[privateNoteKey(taskID: taskID, namespace: namespace)] = note
        workerPrivateTaskNotesRaw = encodeWorkerPrivateNotes(notes)
    }

    private func privateNoteKey(taskID: UUID, namespace: String) -> String {
        "\(namespace)|\(profilePhoneNumber)|\(taskID.uuidString)"
    }

    private func workerPrivateNotesStorage() -> [String: String] {
        decodeWorkerPrivateNotes(workerPrivateTaskNotesRaw)
    }

    private func setPersonalTodoCompletion(todoID: UUID, isCompleted: Bool) {
        guard let sectionID = currentSection?.id, let memberID = currentMember?.id else { return }
        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
              let memberIndex = sections[sectionIndex].members.firstIndex(where: { $0.id == memberID }),
              let todoIndex = sections[sectionIndex].members[memberIndex].todos.firstIndex(where: { $0.id == todoID }) else { return }

        sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted = isCompleted
        managerSectionsRaw = encodeSections(sections)
    }

    private func groupChatBinding(for id: UUID) -> Binding<SectionGroupChat>? {
        guard let section = currentSection,
              let sectionIndex = decodeSections(from: managerSectionsRaw).firstIndex(where: { $0.id == section.id }),
              decodeSections(from: managerSectionsRaw)[sectionIndex].groupChats.firstIndex(where: { $0.id == id }) != nil else {
            return nil
        }

        return Binding(
            get: {
                let sections = decodeSections(from: managerSectionsRaw)
                guard let freshSectionIndex = sections.firstIndex(where: { $0.id == section.id }),
                      let freshChatIndex = sections[freshSectionIndex].groupChats.firstIndex(where: { $0.id == id }) else {
                    return SectionGroupChat(name: "", createdAt: "")
                }
                return sections[freshSectionIndex].groupChats[freshChatIndex]
            },
            set: { updatedChat in
                var sections = decodeSections(from: managerSectionsRaw)
                guard let freshSectionIndex = sections.firstIndex(where: { $0.id == section.id }),
                      let freshChatIndex = sections[freshSectionIndex].groupChats.firstIndex(where: { $0.id == id }) else {
                    return
                }
                sections[freshSectionIndex].groupChats[freshChatIndex] = updatedChat
                managerSectionsRaw = encodeSections(sections)
            }
        )
    }

    private func latestMessagePreview(for chat: SectionGroupChat) -> String {
        guard let lastMessage = chat.messages.last else { return "No messages yet." }
        switch lastMessage.messageType {
        case .text:
            return "\(lastMessage.sender): \(lastMessage.text)"
        case .photo:
            return "\(lastMessage.sender): Photo"
        case .video:
            return "\(lastMessage.sender): Video"
        }
    }

    private func saveSectionUpdates() {
        managerSectionsRaw = encodeSections(decodeSections(from: managerSectionsRaw))
    }

    private func clockIn() {
        guard let sectionID = currentSection?.id, let memberID = currentMember?.id else { return }
        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
              let memberIndex = sections[sectionIndex].members.firstIndex(where: { $0.id == memberID }) else { return }

        sections[sectionIndex].members[memberIndex].clockInTime = Date()
        sections[sectionIndex].members[memberIndex].clockOutTime = nil
        sections[sectionIndex].members[memberIndex].isOnSite = true
        managerSectionsRaw = encodeSections(sections)
    }

    private func clockOut() {
        guard let sectionID = currentSection?.id, let memberID = currentMember?.id else { return }
        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }),
              let memberIndex = sections[sectionIndex].members.firstIndex(where: { $0.id == memberID }) else { return }

        sections[sectionIndex].members[memberIndex].clockOutTime = Date()
        sections[sectionIndex].members[memberIndex].isOnSite = false
        managerSectionsRaw = encodeSections(sections)
    }
}
