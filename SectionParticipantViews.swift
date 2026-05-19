//
//  SectionParticipantViews.swift
//  test
//

import SwiftUI

struct ManagerAssignedSectionDashboardView: View {
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

    private var latestSectionAlert: SectionAlert? {
        currentSection?.alerts.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        List {
            if let section = currentSection {
                if let latestSectionAlert {
                    Section(localized("Alert", language)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(latestSectionAlert.title, systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text(latestSectionAlert.message)
                                .font(.body)
                            Text(latestSectionAlert.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

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
                                            },
                                            onAddSharedPhoto: { attachment in
                                                addTaskAttachment(attachment, to: task.id)
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
        .navigationTitle(currentSection?.name ?? localized("Leadership Crews", language))
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

    private func addTaskAttachment(_ attachment: TaskAttachment, to taskID: UUID) {
        guard let section = currentSection else { return }

        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == section.id }),
              let taskIndex = sections[sectionIndex].sectionTasks.firstIndex(where: { $0.id == taskID }) else { return }

        sections[sectionIndex].sectionTasks[taskIndex].attachments.append(attachment)
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
