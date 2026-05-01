//
//  WorkerViews.swift
//  test
//

import SwiftUI
import OSLog

struct WorkerSectionTaskItem: Identifiable {
    let sectionID: UUID
    let sectionName: String
    let memberID: UUID
    let task: SectionTask

    var id: UUID { task.id }
}

struct WorkerPersonalTodoItem: Identifiable {
    let sectionID: UUID
    let sectionName: String
    let memberID: UUID
    let todo: MemberTodo

    var id: UUID { todo.id }
}

struct WorkerHomeView: View {
    let profileName: String
    let profilePhoneNumber: String
    let sectionName: String
    let sectionCode: String
    let onSignOut: () -> Void
    @Environment(BluetoothManager.self) private var bluetoothManager
    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("workerPrivateTaskNotesJSON") private var workerPrivateTaskNotesRaw = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @State private var showARCVisor = false

    private let updates: [CrewMessage] = [
        CrewMessage(sender: "Foreman", text: "Meet at Gate C for safety brief.", time: "6:45 AM"),
        CrewMessage(sender: "Site Crew Lead", text: "Concrete delivery moved to 10:30 AM.", time: "7:20 AM"),
        CrewMessage(sender: "Safety Lead", text: "High-wind alert after 2 PM.", time: "8:05 AM")
    ]

    private var currentSection: ManagerSection? {
        decodeSections(from: managerSectionsRaw).first(where: { $0.codeWord == sectionCode })
    }

    private var relatedSections: [ManagerSection] {
        guard let currentSection else { return [] }
        let allSections = decodeSections(from: managerSectionsRaw)
        let subsections = allSections.filter {
            $0.parentSectionID == currentSection.id &&
            $0.members.contains(where: { $0.phoneNumber == profilePhoneNumber })
        }
        return [currentSection] + subsections
    }

    private var currentMember: SectionMember? {
        guard let section = currentSection else { return nil }
        return section.members.first(where: { $0.phoneNumber == profilePhoneNumber })
    }

    private var subsectionNames: [String] {
        Array(relatedSections.dropFirst().map(\.name))
    }

    private var assignedSectionTasks: [WorkerSectionTaskItem] {
        var items: [WorkerSectionTaskItem] = []
        for section in relatedSections where section.featureSettings.sectionTasksEnabled {
            guard let member = section.members.first(where: { $0.phoneNumber == profilePhoneNumber }) else { continue }
            let sectionItems = section.sectionTasks
                .filter { $0.assigneeIDs.contains(member.id) }
                .map { WorkerSectionTaskItem(sectionID: section.id, sectionName: section.name, memberID: member.id, task: $0) }
            items.append(contentsOf: sectionItems)
        }
        return items.sorted { $0.task.dueDate < $1.task.dueDate }
    }

    private var personalTodos: [WorkerPersonalTodoItem] {
        var items: [WorkerPersonalTodoItem] = []
        for section in relatedSections where section.featureSettings.personalTodosEnabled {
            guard let member = section.members.first(where: { $0.phoneNumber == profilePhoneNumber }) else { continue }
            let sectionItems = member.todos.map {
                WorkerPersonalTodoItem(sectionID: section.id, sectionName: section.name, memberID: member.id, todo: $0)
            }
            items.append(contentsOf: sectionItems)
        }
        return items.sorted { $0.todo.dueDate < $1.todo.dueDate }
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

    private var arcVisorPayloadContext: ARCVisorPayloadContext {
        ARCVisorPayloadContext(
            userName: abbreviatedDisplayName(profileName),
            roleTitle: "Crew",
            profileAccountID: "",
            profilePhoneNumber: profilePhoneNumber,
            managerSectionsRaw: managerSectionsRaw,
            assignedSectionCodesRaw: "",
            managerPersonalTodosRaw: ""
        )
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ARCLink")
                            .font(.title2.weight(.semibold))
                        Text(greetingText(name: profileName.isEmpty ? localized("Crew", language) : abbreviatedDisplayName(profileName), language: language))
                            .font(.largeTitle.weight(.bold))
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        showARCVisor = true
                    } label: {
                        Label(localized("Open ARCVisor", language), systemImage: "visionpro")
                            .foregroundStyle(Color.arcAccentOrange)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AirQualityMonitorView()
                    } label: {
                        Label(localized("Air Quality Data", language), systemImage: "aqi.medium")
                    }
                }

                if currentSection?.featureSettings.timeClockEnabled ?? true {
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

                if !assignedSectionTasks.isEmpty || relatedSections.contains(where: \.featureSettings.sectionTasksEnabled) {
                    Section(localized("Assigned Tasks", language)) {
                        if assignedSectionTasks.isEmpty {
                            Text("No section tasks assigned to you yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(assignedSectionTasks) { taskItem in
                                HStack(alignment: .top, spacing: 12) {
                                    Button {
                                        setTaskCompletion(taskItem: taskItem, isCompleted: !isTaskMarkedDone(taskItem))
                                    } label: {
                                        Image(systemName: isTaskCompleted(taskItem) ? "checkmark.circle.fill" : (isTaskMarkedDone(taskItem) ? "clock.badge.checkmark.fill" : "circle"))
                                            .font(.title3)
                                            .foregroundStyle(isTaskCompleted(taskItem) ? .green : (isTaskMarkedDone(taskItem) ? .orange : .secondary))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)

                                    NavigationLink {
                                        WorkerTaskDetailView(
                                            task: taskItem.task,
                                            isCompleted: isTaskMarkedDone(taskItem),
                                            isVerified: isTaskCompleted(taskItem),
                                            privateNote: workerPrivateNote(for: taskItem.task.id),
                                            onToggleCompleted: { isDone in
                                                setTaskCompletion(taskItem: taskItem, isCompleted: isDone)
                                            },
                                            onSavePrivateNote: { note in
                                                setWorkerPrivateNote(note, for: taskItem.task.id)
                                            }
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(taskItem.task.title)
                                                    .font(.headline)
                                                Spacer()
                                                Text(taskItem.task.priority.title)
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(taskItem.task.priority.color.opacity(0.18), in: Capsule())
                                            }
                                            Text("Due \(taskItem.task.dueDate, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(localized("From", language)): \(taskItem.sectionName)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(localized("Status", language)): \(workerTaskStatusLabel(taskItem))")
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

                if !personalTodos.isEmpty || relatedSections.contains(where: \.featureSettings.personalTodosEnabled) {
                    Section(localized("Personal To-Dos", language)) {
                        if personalTodos.isEmpty {
                            Text("No personal to-dos assigned.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(personalTodos) { todoItem in
                                HStack(alignment: .top, spacing: 12) {
                                    Button {
                                        setPersonalTodoCompletion(todoItem: todoItem, isCompleted: !isPersonalTodoCompleted(todoItem.todo))
                                    } label: {
                                        Image(systemName: personalTodoStatusImage(todoItem.todo))
                                            .font(.title3)
                                            .foregroundStyle(personalTodoStatusColor(todoItem.todo))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 2)

                                    NavigationLink {
                                        WorkerPersonalTodoDetailView(
                                            todo: todoItem.todo,
                                            privateNote: workerPrivateNote(for: todoItem.todo.id, namespace: "personal"),
                                            onToggleCompleted: { isDone in
                                                setPersonalTodoCompletion(todoItem: todoItem, isCompleted: isDone)
                                            },
                                            onSavePrivateNote: { note in
                                                setWorkerPrivateNote(note, for: todoItem.todo.id, namespace: "personal")
                                            }
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(todoItem.todo.title)
                                                    .font(.headline)
                                                Spacer()
                                                Text(todoItem.todo.priority.title)
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(todoItem.todo.priority.color.opacity(0.18), in: Capsule())
                                            }
                                            Text("Due \(todoItem.todo.dueDate, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(localized("Status", language)): \(workerPersonalTodoStatusLabel(todoItem.todo))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(localized("From", language)): \(todoItem.sectionName)")
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

                if currentSection?.featureSettings.groupChatsEnabled ?? true {
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
                                            onSave: saveWorkerSectionUpdates
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

                Section("Crew Updates") {
                    ForEach(updates) { update in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(update.sender)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(update.time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(update.text)
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    NavigationLink {
                        WorkerProfileDetailView(
                            profileName: profileName,
                            sectionName: sectionName,
                            sectionCode: sectionCode,
                            subsectionNames: subsectionNames,
                            todayClockIn: todayClockIn,
                            todayClockOut: todayClockOut
                        )
                    } label: {
                        Label(localized("My Profile", language), systemImage: "person.crop.circle")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        onSignOut()
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .sheet(isPresented: $showARCVisor) {
            NavigationView {
                ARCVisorHubView(payloadContext: arcVisorPayloadContext)
                    .environment(bluetoothManager)
            }
            .navigationViewStyle(.stack)
        }
        .onAppear {
            managerSectionsRaw = encodeSections(mergedSectionsWithDemoSection(from: managerSectionsRaw))
        }
    }

    private func isTaskCompleted(_ taskItem: WorkerSectionTaskItem) -> Bool {
        taskItem.task.requiresAcknowledgement
            ? taskItem.task.verifiedMemberIDs.contains(taskItem.memberID)
            : taskItem.task.doneMemberIDs.contains(taskItem.memberID)
    }

    private func isTaskMarkedDone(_ taskItem: WorkerSectionTaskItem) -> Bool {
        taskItem.task.doneMemberIDs.contains(taskItem.memberID)
    }

    private func setTaskCompletion(taskItem: WorkerSectionTaskItem, isCompleted: Bool) {
        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == taskItem.sectionID }),
              let taskIndex = sections[sectionIndex].sectionTasks.firstIndex(where: { $0.id == taskItem.task.id }) else { return }

        if isCompleted {
            if !sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.contains(taskItem.memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.append(taskItem.memberID)
            }
            if !sections[sectionIndex].sectionTasks[taskIndex].requiresAcknowledgement,
               !sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.contains(taskItem.memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.append(taskItem.memberID)
            }
        } else {
            sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.removeAll(where: { $0 == taskItem.memberID })
            sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.removeAll(where: { $0 == taskItem.memberID })
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

    private func setPersonalTodoCompletion(todoItem: WorkerPersonalTodoItem, isCompleted: Bool) {
        var sections = decodeSections(from: managerSectionsRaw)
        guard let sectionIndex = sections.firstIndex(where: { $0.id == todoItem.sectionID }),
              let memberIndex = sections[sectionIndex].members.firstIndex(where: { $0.id == todoItem.memberID }),
              let todoIndex = sections[sectionIndex].members[memberIndex].todos.firstIndex(where: { $0.id == todoItem.todo.id }) else { return }

        sections[sectionIndex].members[memberIndex].todos[todoIndex].isMarkedDone = isCompleted
        if sections[sectionIndex].members[memberIndex].todos[todoIndex].requiresAcknowledgement {
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted = false
        } else {
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted = isCompleted
        }
        managerSectionsRaw = encodeSections(sections)
    }

    private func isPersonalTodoCompleted(_ todo: MemberTodo) -> Bool {
        todo.requiresAcknowledgement ? todo.isCompleted : todo.isMarkedDone
    }

    private func workerPersonalTodoStatusLabel(_ todo: MemberTodo) -> String {
        if todo.requiresAcknowledgement {
            if todo.isCompleted {
                return localized("Verified", language)
            }
            if todo.isMarkedDone {
                return localized("To Verify", language)
            }
            return localized("Assigned", language)
        }
        return todo.isMarkedDone ? localized("Done", language) : localized("Assigned", language)
    }

    private func personalTodoStatusImage(_ todo: MemberTodo) -> String {
        if todo.requiresAcknowledgement {
            if todo.isCompleted {
                return "checkmark.circle.fill"
            }
            if todo.isMarkedDone {
                return "clock.badge.checkmark.fill"
            }
            return "circle"
        }
        return todo.isMarkedDone ? "checkmark.circle.fill" : "circle"
    }

    private func personalTodoStatusColor(_ todo: MemberTodo) -> Color {
        if todo.requiresAcknowledgement {
            if todo.isCompleted {
                return .green
            }
            if todo.isMarkedDone {
                return .orange
            }
            return .secondary
        }
        return todo.isMarkedDone ? .green : .secondary
    }

    private func workerTaskStatusLabel(_ taskItem: WorkerSectionTaskItem) -> String {
        if taskItem.task.requiresAcknowledgement {
            if taskItem.task.verifiedMemberIDs.contains(taskItem.memberID) {
                return localized("Verified", language)
            }
            if taskItem.task.doneMemberIDs.contains(taskItem.memberID) {
                return localized("To Verify", language)
            }
            return localized("Assigned", language)
        }
        return taskItem.task.doneMemberIDs.contains(taskItem.memberID) ? localized("Done", language) : localized("Assigned", language)
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

    private func saveWorkerSectionUpdates() {
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

public struct ARCVisorHubView: View {
    let payloadContext: ARCVisorPayloadContext
    @Environment(BluetoothManager.self) private var bluetoothManager
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @State private var bluetoothStatusMessage = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var signedInDisplayName: String {
        payloadContext.userName.isEmpty
            ? localized(payloadContext.roleTitle, language)
            : payloadContext.userName
    }

    private var connectionStatusSymbol: String {
        bluetoothManager.isConnected() ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right"
    }

    private var connectionStatusColor: Color {
        bluetoothManager.isConnected() ? .green : .secondary
    }

    private var latestVisorPayload: String? {
        bluetoothManager.deviceDataString
    }

    private var latestVisorReading: AirQualityReading? {
        guard let latestVisorPayload else { return nil }
        return decodeAirQualityReading(from: latestVisorPayload)
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ARCVisor")
                        .font(.largeTitle.weight(.bold))
                    Text(localized("Augmented Reality Construction Visor", language))
                        .foregroundStyle(.secondary)
                    Text("\(localized("Signed in as", language)) \(signedInDisplayName)")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 6)
            }

            Section(localized("Connection", language)) {
                Label(
                    bluetoothManager.isConnected() ? "Connected!" : "Not Connected",
                    systemImage: connectionStatusSymbol
                ).foregroundStyle(connectionStatusColor)

                if bluetoothManager.isConnected() {
                    if let batteryLevel = latestVisorReading?.battery {
                        HStack {
                            Text(localized("Visor Battery", language))
                            Spacer()
                            Text("\(Int(batteryLevel.rounded()))%")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let payload = latestVisorPayload {
                        Text(payload)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !bluetoothStatusMessage.isEmpty {
                    Text(bluetoothStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(localized("Send Snapshot to Pi", language)) {
                    sendSnapshotToARCVisor()
                }
                .disabled(!bluetoothManager.isConnected())
            }

            Section(localized("What ARCVisor Will Do", language)) {
                Text(localized("Show section tasks, crew locations, and pinned updates in an AR visor view.", language))
                Text(localized("Pull crew assignments and on-site status directly from ARCLink.", language))
                Text(localized("Support field walk-throughs, safety overlays, and visual markups.", language))
            }

            Section(localized("Payload Preview", language)) {
                NavigationLink {
                    ARCVisorPayloadPreviewView(
                        payloadText: arcVisorPayloadPreview,
                        language: language
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Outgoing Device Payload", language))
                            .font(.headline)
                        Text(localized("Review the live JSON currently being prepared for the Raspberry Pi.", language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    ARCVisorDisplayPreviewView(
                        payload: arcVisorPayloadModel,
                        language: language
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Display Preview", language))
                            .font(.headline)
                        Text(localized("Simple micro-OLED mock using the same live payload data.", language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(localized("Connection", language)) {
                Text(localized("ARCVisor connects automatically when the device is available.", language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(localized("Resend Snapshot to Pi", language)) {
                    sendSnapshotToARCVisor()
                }
                .disabled(!bluetoothManager.isConnected())

                Button(localized("Read Device Response", language)) {
                    readFromARCVisor()
                }
                .disabled(!bluetoothManager.isConnected())
            }
        }
        .navigationTitle("ARCVisor")
        .listStyle(.insetGrouped)
    }

    private func sendSnapshotToARCVisor() {
        do {
            let payload = try currentARCVisorPayloadJSON()
            try bluetoothManager.writeString(payload)
            bluetoothStatusMessage = "Sent JSON snapshot to the Raspberry Pi over Bluetooth (\(payload.utf8.count) bytes)."
        } catch BluetoothError.noDevice {
            bluetoothStatusMessage = "No Raspberry Pi Bluetooth device connected."
        } catch BluetoothError.noCharacteristic {
            bluetoothStatusMessage = "Connected Raspberry Pi is missing the ARCVisor data characteristic."
        } catch BluetoothError.invalidArgument {
            bluetoothStatusMessage = "Could not encode ARCVisor payload."
        } catch {
            bluetoothStatusMessage = "Failed to send the JSON snapshot to the Raspberry Pi."
        }
    }

    private func readFromARCVisor() {
        do {
            try bluetoothManager.read()
            bluetoothStatusMessage = "Requested latest data from ARCVisor."
        } catch BluetoothError.noDevice {
            bluetoothStatusMessage = "No ARCVisor device connected."
        } catch BluetoothError.noCharacteristic {
            bluetoothStatusMessage = "Connected device is missing the ARCVisor data characteristic."
        } catch {
            bluetoothStatusMessage = "Failed to read data from ARCVisor."
        }
    }

    private func currentARCVisorPayloadJSON() throws -> String {
        try encodedARCVisorPayload(from: payloadContext)
    }

    private var arcVisorPayloadPreview: String {
        (try? currentARCVisorPayloadJSON()) ?? localized("Payload unavailable.", language)
    }

    private var arcVisorPayloadModel: ARCVisorPayload {
        arcVisorPayload(from: payloadContext)
    }
}

private struct ARCVisorPayloadPreviewView: View {
    let payloadText: String
    let language: AppLanguage
    @State private var didCopyPayload = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    UIPasteboard.general.string = payloadText
                    didCopyPayload = true
                } label: {
                    Label(localized("Copy JSON Payload", language), systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                if didCopyPayload {
                    Text(localized("Payload copied to clipboard.", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(payloadText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localized("Outgoing Device Payload", language))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ARCVisorDisplayPreviewView: View {
    let payload: ARCVisorPayload
    let language: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ARCV")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Text(payload.userName.isEmpty ? "--" : payload.userName)
                        .lineLimit(1)
                }

                Divider()
                    .overlay(Color.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Top To-Dos", language))
                        .font(.caption.weight(.bold))
                    ForEach(Array(payload.topTodos.prefix(3).enumerated()), id: \.offset) { index, todo in
                        Text("\(index + 1). \(todo.priority.prefix(1)) \(todo.title)")
                            .lineLimit(1)
                    }
                    if payload.topTodos.isEmpty {
                        Text("--")
                    }
                }

                Divider()
                    .overlay(Color.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Notifications", language))
                        .font(.caption.weight(.bold))
                    ForEach(Array(payload.notifications.prefix(1).enumerated()), id: \.offset) { _, notification in
                        Text("• \(notification.message)")
                            .lineLimit(1)
                    }
                    if payload.notifications.isEmpty {
                        Text("--")
                    }
                }
            }
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localized("Display Preview", language))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AirQualityMonitorView: View {
    private struct SensorWarning: Identifiable {
        enum Severity {
            case advisory
            case caution
            case danger

            var tint: Color {
                switch self {
                case .advisory:
                    return .yellow
                case .caution:
                    return .orange
                case .danger:
                    return .red
                }
            }

            var systemImage: String {
                switch self {
                case .advisory:
                    return "exclamationmark.circle.fill"
                case .caution:
                    return "exclamationmark.triangle.fill"
                case .danger:
                    return "exclamationmark.octagon.fill"
                }
            }
        }

        let title: String
        let message: String
        let severity: Severity

        var id: String { "\(title)-\(message)" }
    }

    private enum SensorPollingMode: String, CaseIterable, Identifiable {
        case standard
        case elevated
        case continuous

        var id: String { rawValue }

        var intervalSeconds: Double {
            switch self {
            case .standard:
                return 60
            case .elevated:
                return 30
            case .continuous:
                return 15
            }
        }

        func title(for language: AppLanguage) -> String {
            switch self {
            case .standard:
                return localized("Standard (60s)", language)
            case .elevated:
                return localized("Elevated (30s)", language)
            case .continuous:
                return localized("Continuous (15s)", language)
            }
        }
    }

    @Environment(BluetoothManager.self) private var bluetoothManager
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @State private var statusMessage = ""
    @State private var pollingMode: SensorPollingMode = .standard

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var latestPayload: String? {
        bluetoothManager.deviceDataString
    }

    private var latestReading: AirQualityReading? {
        guard let latestPayload else { return nil }
        return decodeAirQualityReading(from: latestPayload)
    }

    private var activeWarnings: [SensorWarning] {
        guard let latestReading else { return [] }

        var warnings: [SensorWarning] = []

        if let carbon = latestReading.carbon {
            if carbon >= 2_000 {
                warnings.append(
                    SensorWarning(
                        title: localized("Air Quality Warning", language),
                        message: localized("Carbon is very high (\(String(format: "%.0f", carbon)) ppm). Move workers to fresh air and check the area immediately.", language),
                        severity: .danger
                    )
                )
            } else if carbon >= 1_000 {
                warnings.append(
                    SensorWarning(
                        title: localized("Air Quality Warning", language),
                        message: localized("Carbon is elevated (\(String(format: "%.0f", carbon)) ppm). Increase ventilation and keep monitoring conditions.", language),
                        severity: .caution
                    )
                )
            } else if carbon >= 800 {
                warnings.append(
                    SensorWarning(
                        title: localized("Air Quality Notice", language),
                        message: localized("Carbon is trending upward (\(String(format: "%.0f", carbon)) ppm). Watch for worsening ventilation.", language),
                        severity: .advisory
                    )
                )
            }
        }

        if let temperatureCelsius = latestReading.temperature {
            let temperatureFahrenheit = (temperatureCelsius * 9 / 5) + 32

            if temperatureFahrenheit >= 103 {
                warnings.append(
                    SensorWarning(
                        title: localized("Heat Warning", language),
                        message: localized("Extreme heat detected (\(String(format: "%.1f", temperatureCelsius)) C / \(String(format: "%.1f", temperatureFahrenheit)) F). Stop heavy work, cool down, hydrate, and check workers now.", language),
                        severity: .danger
                    )
                )
            } else if temperatureFahrenheit >= 95 {
                warnings.append(
                    SensorWarning(
                        title: localized("Heat Warning", language),
                        message: localized("High heat detected (\(String(format: "%.1f", temperatureCelsius)) C / \(String(format: "%.1f", temperatureFahrenheit)) F). Add rest, shade, and water breaks.", language),
                        severity: .caution
                    )
                )
            } else if temperatureFahrenheit >= 88 {
                warnings.append(
                    SensorWarning(
                        title: localized("Heat Notice", language),
                        message: localized("Warm conditions detected (\(String(format: "%.1f", temperatureCelsius)) C / \(String(format: "%.1f", temperatureFahrenheit)) F). Monitor workers for early signs of heat stress.", language),
                        severity: .advisory
                    )
                )
            }
        }

        return warnings
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Air Quality Data", language))
                        .font(.largeTitle.weight(.bold))
                    Text(localized("Use this screen to confirm the Raspberry Pi is sending carbon, temperature, and humidity JSON over Bluetooth.", language))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section(localized("Connection", language)) {
                Label(
                    bluetoothManager.isConnected() ? localized("Connected!", language) : localized("Not Connected", language),
                    systemImage: bluetoothManager.isConnected() ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right"
                )
                .foregroundStyle(bluetoothManager.isConnected() ? .green : .secondary)

                if let lastReceivedAt = bluetoothManager.lastReceivedAt {
                    Text("\(localized("Last Sensor Update", language)): \(lastReceivedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(localized("No sensor data has been received yet.", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(localized("Request Latest Air Quality Reading", language)) {
                    requestLatestReading()
                }
                .disabled(!bluetoothManager.isConnected())

                Picker(localized("Auto Refresh", language), selection: $pollingMode) {
                    ForEach(SensorPollingMode.allCases) { mode in
                        Text(mode.title(for: language)).tag(mode)
                    }
                }

                Text(
                    localized(
                        "ARCLink automatically requests updated sensor data every \(Int(pollingMode.intervalSeconds)) seconds while this screen is open.",
                        language
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(localized("Sensor Readings", language)) {
                sensorValueRow(
                    title: localized("Carbon", language),
                    valueText: latestReading?.carbon.map { String(format: "%.2f ppm", $0) } ?? localized("Unavailable", language)
                )
                sensorValueRow(
                    title: localized("Temperature", language),
                    valueText: latestReading?.temperature.map { temperatureCelsius in
                        let temperatureFahrenheit = (temperatureCelsius * 9 / 5) + 32
                        return String(
                            format: "%.2f C (%.2f F)",
                            temperatureCelsius,
                            temperatureFahrenheit
                        )
                    } ?? localized("Unavailable", language)
                )
                sensorValueRow(
                    title: localized("Humidity", language),
                    valueText: latestReading?.humidity.map { String(format: "%.2f %%", $0) } ?? localized("Unavailable", language)
                )

                if let latestReading, !latestReading.hasAnyReading {
                    Text(localized("JSON received, but the expected air quality keys were not found.", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !activeWarnings.isEmpty {
                Section(localized("Warnings", language)) {
                    ForEach(activeWarnings) { warning in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: warning.severity.systemImage)
                                .foregroundStyle(warning.severity.tint)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(warning.title)
                                    .font(.headline)
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section(localized("Raw JSON", language)) {
                if let latestPayload {
                    Text(latestPayload)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } else {
                    Text(localized("No JSON payload received yet.", language))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(localized("Air Quality Data", language))
        .listStyle(.insetGrouped)
        .task(id: pollingMode) {
            await startAutomaticPolling()
        }
    }

    @ViewBuilder
    private func sensorValueRow(title: String, valueText: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(valueText)
                .foregroundStyle(.secondary)
        }
    }

    private func requestLatestReading() {
        do {
            try bluetoothManager.read()
            statusMessage = localized("Requested the latest air quality reading from the Raspberry Pi.", language)
            
            let data = bluetoothManager.deviceDataString ?? "[No data!]"
            Logger().info("Got: \(data)")
        } catch BluetoothError.noDevice {
            statusMessage = localized("No Raspberry Pi Bluetooth device connected.", language)
        } catch BluetoothError.noCharacteristic {
            statusMessage = localized("Connected device is missing the Bluetooth characteristic.", language)
        } catch {
            statusMessage = localized("Failed to request air quality data.", language)
        }
    }

    @MainActor
    private func requestLatestReadingAutomatically() {
        guard bluetoothManager.isConnected() else { return }

        do {
            try bluetoothManager.read()
        } catch {
            Logger().error("Automatic sensor refresh failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func startAutomaticPolling() async {
        requestLatestReadingAutomatically()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pollingMode.intervalSeconds))
            guard !Task.isCancelled else { return }
            requestLatestReadingAutomatically()
        }
    }
}

    public struct WorkerSectionGroupChatDetailView: View {
        @Binding var chat: SectionGroupChat
        let currentMember: SectionMember
        let onSave: () -> Void
        @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
        @AppStorage("workerSavedChatMessagesJSON") private var workerSavedChatMessagesRaw = ""
        
        @State private var newMessageText = ""
        @State private var showMediaPicker = false
        @State private var showMediaTypeDialog = false
        @State private var selectedMediaType: ChatMessageType = .photo
        
        private var pinnedMessages: [GroupChatMessage] {
            chat.messages.filter { chat.pinnedMessageIDs.contains($0.id) }
        }
        
        private var savedMessages: [GroupChatMessage] {
            let savedIDs = Set(savedMessageIDs)
            return chat.messages.filter { savedIDs.contains($0.id.uuidString) }
        }
        
        private var canWrite: Bool {
            chat.writableMemberIDs.contains(currentMember.id)
        }
        
        private var language: AppLanguage {
            AppLanguage(rawValue: profileLanguageRawValue) ?? .english
        }
        
        private var savedMessageKey: String {
            "\(currentMember.phoneNumber)|\(chat.id.uuidString)"
        }
        
        private var savedMessageIDs: [String] {
            decodeWorkerSavedMessages(workerSavedChatMessagesRaw)[savedMessageKey] ?? []
        }
        
        public var body: some View {
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
                
                if !savedMessages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(savedMessages) { message in
                                Text("🔖 \(messagePreview(message))")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
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
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 30)
                            } else {
                                ForEach(chat.messages) { message in
                                    workerMessageBubble(message)
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
                
                if canWrite {
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
                } else {
                    Text(localized("This chat is read only. Your crew lead can enable write access in chat settings.", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle(chat.name)
            .navigationBarTitleDisplayMode(.inline)
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
        
        @ViewBuilder
        private func workerMessageBubble(_ message: GroupChatMessage) -> some View {
            let isCurrentUser = message.sender == currentMember.name
            if message.messageType == .text {
                HStack {
                    if isCurrentUser {
                        Spacer(minLength: 40)
                    }
                    
                    VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                        Text(message.sender)
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
                        Button(isMessageSavedForCurrentUser(message.id) ? localized("Unsave Message", language) : localized("Save Message", language)) {
                            toggleSavedMessage(message.id)
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
                        workerReactionSummaryView(message)
                    }
                    
                    if !isCurrentUser {
                        Spacer(minLength: 40)
                    }
                }
            } else {
                VStack(alignment: .center, spacing: 6) {
                    Text(message.sender)
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
                    Button(isMessageSavedForCurrentUser(message.id) ? localized("Unsave Message", language) : localized("Save Message", language)) {
                        toggleSavedMessage(message.id)
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
                    workerReactionSummaryView(message)
                }
            }
        }
        
        private func sendMessage() {
            let cleanedText = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedText.isEmpty, canWrite else { return }
            
            chat.messages.append(
                GroupChatMessage(
                    sender: currentMember.name,
                    text: cleanedText,
                    time: shortTimeString(),
                    messageType: .text
                )
            )
            onSave()
            newMessageText = ""
        }
        
        private func sendMediaMessage(type: ChatMessageType, label: String) {
            guard canWrite else { return }
            chat.messages.append(
                GroupChatMessage(
                    sender: currentMember.name,
                    text: "",
                    time: shortTimeString(),
                    messageType: type,
                    attachmentLabel: label
                )
            )
            onSave()
        }
        
        private func toggleReaction(messageID: UUID, emoji: String) {
            guard let index = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
            if let reactionIndex = chat.messages[index].reactions.firstIndex(where: { $0.emoji == emoji && $0.by == currentMember.name }) {
                chat.messages[index].reactions.remove(at: reactionIndex)
            } else {
                chat.messages[index].reactions.append(
                    MessageReaction(emoji: emoji, by: currentMember.name)
                )
            }
            onSave()
        }
        
        private func isMessageSavedForCurrentUser(_ messageID: UUID) -> Bool {
            savedMessageIDs.contains(messageID.uuidString)
        }
        
        private func toggleSavedMessage(_ messageID: UUID) {
            var savedMessagesByChat = decodeWorkerSavedMessages(workerSavedChatMessagesRaw)
            var updatedSavedIDs = savedMessagesByChat[savedMessageKey] ?? []
            
            if let index = updatedSavedIDs.firstIndex(of: messageID.uuidString) {
                updatedSavedIDs.remove(at: index)
            } else {
                updatedSavedIDs.append(messageID.uuidString)
            }
            
            if updatedSavedIDs.isEmpty {
                savedMessagesByChat.removeValue(forKey: savedMessageKey)
            } else {
                savedMessagesByChat[savedMessageKey] = updatedSavedIDs
            }
            
            workerSavedChatMessagesRaw = encodeWorkerSavedMessages(savedMessagesByChat)
        }
        
        private func scrollToBottom(using proxy: ScrollViewProxy) {
            guard let last = chat.messages.last else { return }
            DispatchQueue.main.async {
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
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
        
        @ViewBuilder
        private func workerReactionSummaryView(_ message: GroupChatMessage) -> some View {
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

public struct WorkerProfileDetailView: View {
    let profileName: String
    let sectionName: String
    let sectionCode: String
    let subsectionNames: [String]
    let todayClockIn: Date?
    let todayClockOut: Date?
    
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
    
    public var body: some View {
        List {
            Section(localized("Profile", language)) {
                Text(profileName.isEmpty ? "Crew" : profileName)
                Text(localized("Role: Crew", language))
                    .foregroundStyle(.secondary)
                if !savedProfileEmail.isEmpty {
                    Text(localized("Email", language) + ": \(savedProfileEmail)")
                        .foregroundStyle(.secondary)
                }
                if !sectionName.isEmpty {
                    Text(localized("Section", language) + ": \(sectionName)")
                        .foregroundStyle(.secondary)
                }
                if !sectionCode.isEmpty {
                    Text(localized("Code Word", language) + ": \(sectionCode)")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section(localized("Section Membership", language)) {
                if !sectionName.isEmpty {
                    Text(localized("Section", language) + ": \(sectionName)")
                        .foregroundStyle(.secondary)
                }
                
                if subsectionNames.isEmpty {
                    Text(localized("No subsections assigned.", language))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Subsections", language))
                            .font(.subheadline.weight(.semibold))
                        ForEach(subsectionNames, id: \.self) { name in
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section(localized("Today", language)) {
                if let todayClockIn {
                    Text(localized("Clocked In", language) + ": \(todayClockIn.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                if let todayClockOut {
                    Text(localized("Clocked Out", language) + ": \(todayClockOut.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                if todayClockIn == nil, todayClockOut == nil {
                    Text(localized("No time clock activity recorded today.", language))
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
        }
        .navigationTitle(localized("My Profile", language))
        .listStyle(.insetGrouped)
        .onAppear {
            emailDraft = savedProfileEmail
            selectedLanguage = AppLanguage(rawValue: savedProfileLanguageRawValue) ?? .english
        }
    }
    
    private func saveEmail() {
        let cleanedEmail = emailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        savedProfileEmail = cleanedEmail
        registeredProfilesRaw = updatingRegisteredProfile(
            rawValue: registeredProfilesRaw,
            accountID: savedProfileAccountID,
            phoneNumber: savedProfilePhoneNumber,
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
            accountID: savedProfileAccountID,
            phoneNumber: savedProfilePhoneNumber,
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
            accountID: savedProfileAccountID,
            phoneNumber: savedProfilePhoneNumber,
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

public struct WorkerTaskDetailView: View {
    let task: SectionTask
    let isCompleted: Bool
    let isVerified: Bool
    let privateNote: String
    let onToggleCompleted: (Bool) -> Void
    let onSavePrivateNote: (String) -> Void
    
    @State private var completedState = false
    @State private var privateNoteDraft = ""
    
    public var body: some View {
        List {
            Section("Task") {
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
                
                if !task.siteName.isEmpty {
                    Text("Site: \(task.siteName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !task.locationDetails.isEmpty {
                    Text("Location: \(task.locationDetails)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !task.descriptionText.isEmpty {
                Section("Description") {
                    Text(task.descriptionText)
                }
            }
            
            if !task.checklistItems.isEmpty {
                Section("Checklist Items") {
                    ForEach(task.checklistItems) { item in
                        Label(item.title, systemImage: "checklist")
                    }
                }
            }
            
            if !task.attachments.isEmpty {
                Section("Attachments") {
                    ForEach(task.attachments) { attachment in
                        Label(attachment.label, systemImage: attachment.type.systemImage)
                    }
                }
            }
            
            Section("Status") {
                Toggle(task.requiresAcknowledgement ? "Mark Done" : "Mark Complete", isOn: $completedState)
                    .onChange(of: completedState) { newValue in
                        onToggleCompleted(newValue)
                    }
                
                if task.requiresAcknowledgement && isVerified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if task.requiresAcknowledgement && completedState {
                    Label("Waiting for crew lead verification", systemImage: "clock.badge.checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Crew Lead Notes") {
                if task.managerNotes.isEmpty {
                    Text("No crew lead notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(task.managerNotes)
                }
            }
            
            Section("My Private Notes") {
                TextEditor(text: $privateNoteDraft)
                    .frame(minHeight: 120)
                
                Button("Save Private Note") {
                    onSavePrivateNote(privateNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Task")
        .onAppear {
            completedState = isCompleted
            privateNoteDraft = privateNote
        }
    }
}

struct WorkerPersonalTodoDetailView: View {
    let todo: MemberTodo
    let privateNote: String
    let onToggleCompleted: (Bool) -> Void
    let onSavePrivateNote: (String) -> Void
    
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @State private var completedState = false
    @State private var privateNoteDraft = ""
    
    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }
    
    var body: some View {
        List {
            Section(localized("To-Do", language)) {
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
                Text(localized("Due", language) + " \(todo.dueDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !todo.siteName.isEmpty {
                    Text("\(localized("Site", language)): \(todo.siteName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !todo.locationDetails.isEmpty {
                    Text("\(localized("Location", language)): \(todo.locationDetails)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if !todo.descriptionText.isEmpty {
                Section(localized("Description", language)) {
                    Text(todo.descriptionText)
                }
            }
            
            if !todo.checklistItems.isEmpty {
                Section(localized("Checklist Items", language)) {
                    ForEach(todo.checklistItems) { item in
                        Label(item.title, systemImage: "checklist")
                    }
                }
            }
            
            if !todo.attachments.isEmpty {
                Section(localized("Attachments", language)) {
                    ForEach(todo.attachments) { attachment in
                        Label(attachment.label, systemImage: attachment.type.systemImage)
                    }
                }
            }
            
            Section(localized("Status", language)) {
                Toggle(todo.requiresAcknowledgement ? localized("Mark Done", language) : localized("Mark Complete", language), isOn: $completedState)
                    .onChange(of: completedState) { newValue in
                        onToggleCompleted(newValue)
                    }
                
                if todo.requiresAcknowledgement && todo.isCompleted {
                    Label(localized("Verified", language), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if todo.requiresAcknowledgement && completedState {
                    Label(localized("Waiting for crew lead verification", language), systemImage: "clock.badge.checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section(localized("Crew Lead Notes", language)) {
                if todo.managerNotes.isEmpty {
                    Text(localized("No crew lead notes yet.", language))
                        .foregroundStyle(.secondary)
                } else {
                    Text(todo.managerNotes)
                }
            }
            
            Section(localized("My Private Notes", language)) {
                TextEditor(text: $privateNoteDraft)
                    .frame(minHeight: 120)
                
                Button(localized("Save Private Note", language)) {
                    onSavePrivateNote(privateNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(localized("To-Do", language))
        .onAppear {
            completedState = todo.isMarkedDone
            privateNoteDraft = privateNote
        }
    }
}
