//
//  AppSupport.swift
//  test
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AppIntents

extension Color {
    static let arcAccentOrange = Color(red: 0.92, green: 0.45, blue: 0.12)
    static let arcAccentOrangeSoft = Color(red: 0.98, green: 0.72, blue: 0.32)
}

let arcLinkDemoAppStorageSuiteName = "ARCLinkDemoDefaults"

func arcLinkActiveUserDefaults() -> UserDefaults {
    let standardDefaults = UserDefaults.standard
    guard standardDefaults.bool(forKey: "isInDemoMode") else {
        return standardDefaults
    }
    return UserDefaults(suiteName: arcLinkDemoAppStorageSuiteName) ?? standardDefaults
}

private enum ARCLinkTaskCompletionResult {
    case completed(String)
    case alreadyCompleted(String)
    case notFound
}

private struct ARCLinkTaskSummary {
    let title: String
    let dueDate: Date
    let sourceLabel: String
}

private func normalizedTaskMatchTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func memberMatchesCurrentProfile(_ member: SectionMember, accountID: String, phoneNumber: String) -> Bool {
    (!accountID.isEmpty && member.accountID == accountID) || (!phoneNumber.isEmpty && member.phoneNumber == phoneNumber)
}

private func markManagerTaskComplete(named title: String, defaults: UserDefaults) -> ARCLinkTaskCompletionResult {
    let matchTitle = normalizedTaskMatchTitle(title)

    var managerTodos = decodeMemberTodos(from: defaults.string(forKey: "managerPersonalTodosJSON") ?? "")
    if let todoIndex = managerTodos.firstIndex(where: { normalizedTaskMatchTitle($0.title) == matchTitle }) {
        if managerTodos[todoIndex].isCompleted {
            return .alreadyCompleted(managerTodos[todoIndex].title)
        }
        managerTodos[todoIndex].isMarkedDone = true
        managerTodos[todoIndex].isCompleted = true
        defaults.set(encodeMemberTodos(managerTodos), forKey: "managerPersonalTodosJSON")
        return .completed(managerTodos[todoIndex].title)
    }

    let accountID = defaults.string(forKey: "profileAccountID") ?? ""
    let phoneNumber = defaults.string(forKey: "profilePhoneNumber") ?? ""
    var sections = decodeSections(from: defaults.string(forKey: "managerSectionsJSON") ?? "")

    for sectionIndex in sections.indices {
        guard let memberIndex = sections[sectionIndex].members.firstIndex(where: {
            memberMatchesCurrentProfile($0, accountID: accountID, phoneNumber: phoneNumber)
        }) else { continue }

        let memberID = sections[sectionIndex].members[memberIndex].id

        if let todoIndex = sections[sectionIndex].members[memberIndex].todos.firstIndex(where: {
            normalizedTaskMatchTitle($0.title) == matchTitle
        }) {
            if sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted {
                return .alreadyCompleted(sections[sectionIndex].members[memberIndex].todos[todoIndex].title)
            }
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isMarkedDone = true
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted = true
            defaults.set(encodeSections(sections), forKey: "managerSectionsJSON")
            return .completed(sections[sectionIndex].members[memberIndex].todos[todoIndex].title)
        }

        if let taskIndex = sections[sectionIndex].sectionTasks.firstIndex(where: {
            normalizedTaskMatchTitle($0.title) == matchTitle && $0.assigneeIDs.contains(memberID)
        }) {
            let task = sections[sectionIndex].sectionTasks[taskIndex]
            if task.verifiedMemberIDs.contains(memberID) {
                return .alreadyCompleted(task.title)
            }
            if !sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.contains(memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.append(memberID)
            }
            if !sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.contains(memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.append(memberID)
            }
            defaults.set(encodeSections(sections), forKey: "managerSectionsJSON")
            return .completed(task.title)
        }
    }

    return .notFound
}

private func markWorkerTaskComplete(named title: String, defaults: UserDefaults) -> ARCLinkTaskCompletionResult {
    let matchTitle = normalizedTaskMatchTitle(title)
    let accountID = defaults.string(forKey: "profileAccountID") ?? ""
    let phoneNumber = defaults.string(forKey: "profilePhoneNumber") ?? ""
    var sections = decodeSections(from: defaults.string(forKey: "managerSectionsJSON") ?? "")

    for sectionIndex in sections.indices {
        guard let memberIndex = sections[sectionIndex].members.firstIndex(where: {
            memberMatchesCurrentProfile($0, accountID: accountID, phoneNumber: phoneNumber)
        }) else { continue }

        let memberID = sections[sectionIndex].members[memberIndex].id

        if let todoIndex = sections[sectionIndex].members[memberIndex].todos.firstIndex(where: {
            normalizedTaskMatchTitle($0.title) == matchTitle
        }) {
            let todo = sections[sectionIndex].members[memberIndex].todos[todoIndex]
            if todo.requiresAcknowledgement ? todo.isMarkedDone : todo.isCompleted {
                return .alreadyCompleted(todo.title)
            }
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isMarkedDone = true
            sections[sectionIndex].members[memberIndex].todos[todoIndex].isCompleted = !todo.requiresAcknowledgement
            defaults.set(encodeSections(sections), forKey: "managerSectionsJSON")
            return .completed(todo.title)
        }

        if let taskIndex = sections[sectionIndex].sectionTasks.firstIndex(where: {
            normalizedTaskMatchTitle($0.title) == matchTitle && $0.assigneeIDs.contains(memberID)
        }) {
            let task = sections[sectionIndex].sectionTasks[taskIndex]
            if task.requiresAcknowledgement ? task.doneMemberIDs.contains(memberID) : task.verifiedMemberIDs.contains(memberID) {
                return .alreadyCompleted(task.title)
            }
            if !sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.contains(memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].doneMemberIDs.append(memberID)
            }
            if !task.requiresAcknowledgement &&
                !sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.contains(memberID) {
                sections[sectionIndex].sectionTasks[taskIndex].verifiedMemberIDs.append(memberID)
            }
            defaults.set(encodeSections(sections), forKey: "managerSectionsJSON")
            return .completed(task.title)
        }
    }

    return .notFound
}

private func markCurrentUserTaskComplete(named title: String, defaults: UserDefaults) -> ARCLinkTaskCompletionResult {
    let roleRawValue = defaults.string(forKey: "profileRole") ?? AppRole.worker.rawValue
    switch AppRole(rawValue: roleRawValue) ?? .worker {
    case .manager:
        return markManagerTaskComplete(named: title, defaults: defaults)
    case .worker:
        return markWorkerTaskComplete(named: title, defaults: defaults)
    }
}

private func currentUserTaskSummaries(defaults: UserDefaults) -> [ARCLinkTaskSummary] {
    let roleRawValue = defaults.string(forKey: "profileRole") ?? AppRole.worker.rawValue
    switch AppRole(rawValue: roleRawValue) ?? .worker {
    case .manager:
        return currentManagerTaskSummaries(defaults: defaults)
    case .worker:
        return currentWorkerTaskSummaries(defaults: defaults)
    }
}

private func currentManagerTaskSummaries(defaults: UserDefaults) -> [ARCLinkTaskSummary] {
    var summaries = decodeMemberTodos(from: defaults.string(forKey: "managerPersonalTodosJSON") ?? "").map {
        ARCLinkTaskSummary(title: $0.title, dueDate: $0.dueDate, sourceLabel: "My To-Do")
    }

    let sections = decodeSections(from: defaults.string(forKey: "managerSectionsJSON") ?? "")
    let assignedSectionCodes = Set(decodeStringArray(from: defaults.string(forKey: "managerAssignedSectionCodesJSON") ?? ""))
    let accountID = defaults.string(forKey: "profileAccountID") ?? ""
    let phoneNumber = defaults.string(forKey: "profilePhoneNumber") ?? ""

    for section in sections where assignedSectionCodes.contains(section.codeWord) {
        guard let member = section.members.first(where: {
            memberMatchesCurrentProfile($0, accountID: accountID, phoneNumber: phoneNumber)
        }) else { continue }

        summaries.append(contentsOf: section.sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .map { ARCLinkTaskSummary(title: $0.title, dueDate: $0.dueDate, sourceLabel: section.name) })

        summaries.append(contentsOf: member.todos.map {
            ARCLinkTaskSummary(title: $0.title, dueDate: $0.dueDate, sourceLabel: section.name)
        })
    }

    return summaries.sorted { $0.dueDate < $1.dueDate }
}

private func currentWorkerTaskSummaries(defaults: UserDefaults) -> [ARCLinkTaskSummary] {
    let sections = decodeSections(from: defaults.string(forKey: "managerSectionsJSON") ?? "")
    let accountID = defaults.string(forKey: "profileAccountID") ?? ""
    let phoneNumber = defaults.string(forKey: "profilePhoneNumber") ?? ""
    var summaries: [ARCLinkTaskSummary] = []

    for section in sections {
        guard let member = section.members.first(where: {
            memberMatchesCurrentProfile($0, accountID: accountID, phoneNumber: phoneNumber)
        }) else { continue }

        summaries.append(contentsOf: section.sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .map { ARCLinkTaskSummary(title: $0.title, dueDate: $0.dueDate, sourceLabel: section.name) })

        summaries.append(contentsOf: member.todos.map {
            ARCLinkTaskSummary(title: $0.title, dueDate: $0.dueDate, sourceLabel: section.name)
        })
    }

    return summaries.sorted { $0.dueDate < $1.dueDate }
}

private func currentUserTasksDialog(defaults: UserDefaults) -> IntentDialog {
    let summaries = currentUserTaskSummaries(defaults: defaults)
    guard !summaries.isEmpty else {
        return IntentDialog("You have no tasks assigned right now.")
    }

    let topTasks = summaries.prefix(3).map { summary in
        "\(summary.title) from \(summary.sourceLabel)"
    }

    if summaries.count == 1, let onlyTask = topTasks.first {
        return IntentDialog("You have 1 task: \(onlyTask).")
    }

    let spokenList = ListFormatter.localizedString(byJoining: topTasks)
    if summaries.count <= 3 {
        return IntentDialog("You have \(summaries.count) tasks: \(spokenList).")
    }

    return IntentDialog("You have \(summaries.count) tasks. The next 3 are \(spokenList).")
}

private func normalizedPersonMatchName(_ name: String) -> String {
    name
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: ".", with: "")
}

private func currentOwnedSections(defaults: UserDefaults) -> [ManagerSection] {
    let profileAccountID = defaults.string(forKey: "profileAccountID") ?? ""
    let sections = decodeSections(from: defaults.string(forKey: "managerSectionsJSON") ?? "")
    let demoOwnerID = defaultManagerDemoProfile().accountID

    return sections.filter { section in
        if let ownerAccountID = section.ownerAccountID {
            return ownerAccountID == profileAccountID
        }
        return profileAccountID == demoOwnerID
    }
}

private func assignTaskToCrewMember(
    title: String,
    crewMemberName: String,
    dueDate: Date?,
    sectionName: String?,
    defaults: UserDefaults
) -> String? {
    let roleRawValue = defaults.string(forKey: "profileRole") ?? AppRole.manager.rawValue
    guard AppRole(rawValue: roleRawValue) == .manager else { return nil }

    let normalizedMemberName = normalizedPersonMatchName(crewMemberName)
    let normalizedSectionName = sectionName.map(normalizedTaskMatchTitle)
    let nicknames = decodeManagerCrewNicknames(from: defaults.string(forKey: "managerCrewNicknamesJSON") ?? "")
    var sections = decodeSections(from: defaults.string(forKey: "managerSectionsJSON") ?? "")
    let ownedSectionIDs = Set(currentOwnedSections(defaults: defaults).map(\.id))

    for sectionIndex in sections.indices where ownedSectionIDs.contains(sections[sectionIndex].id) {
        if let normalizedSectionName,
           normalizedTaskMatchTitle(sections[sectionIndex].name) != normalizedSectionName {
            continue
        }

        guard let member = sections[sectionIndex].members.first(where: {
            let fullName = normalizedPersonMatchName($0.name)
            let firstName = normalizedPersonMatchName(splitFullName($0.name).firstName)
            let displayName = normalizedPersonMatchName(managerDisplayName(for: $0, nicknames: nicknames))
            return fullName == normalizedMemberName ||
                firstName == normalizedMemberName ||
                displayName == normalizedMemberName
        }) else {
            continue
        }

        let task = SectionTask(
            title: title,
            priority: .medium,
            dueDate: dueDate ?? Date(),
            siteName: sections[sectionIndex].name,
            requiresAcknowledgement: false,
            assigneeIDs: [member.id]
        )
        sections[sectionIndex].sectionTasks.insert(task, at: 0)
        defaults.set(encodeSections(sections), forKey: "managerSectionsJSON")
        return "\(task.title) assigned to \(member.name) in \(sections[sectionIndex].name)."
    }

    return nil
}

func decodeRegisteredProfiles(from rawValue: String) -> [RegisteredProfile] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [] }
    return (try? JSONDecoder().decode([RegisteredProfile].self, from: data)) ?? []
}

func encodeRegisteredProfiles(_ profiles: [RegisteredProfile]) -> String {
    guard let data = try? JSONEncoder().encode(profiles),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func defaultWorkerDemoProfile() -> RegisteredProfile {
    RegisteredProfile(
        accountID: "200001",
        name: "Jake Reynolds",
        phoneNumber: "4155551023",
        email: "worker.demo@arclink.local",
        role: .worker,
        password: "worker123"
    )
}

func defaultManagerDemoProfile() -> RegisteredProfile {
    RegisteredProfile(
        accountID: "100001",
        name: "Bob Builder",
        phoneNumber: "4155550001",
        email: "manager.demo@arclink.local",
        role: .manager,
        password: "manager123"
    )
}

func mergedRegisteredProfilesWithDemoAccounts(from rawValue: String) -> [RegisteredProfile] {
    var profiles = decodeRegisteredProfiles(from: rawValue)

    for demoProfile in [defaultWorkerDemoProfile(), defaultManagerDemoProfile()] {
        if let index = profiles.firstIndex(where: {
            $0.accountID == demoProfile.accountID || $0.phoneNumber == demoProfile.phoneNumber
        }) {
            profiles[index] = demoProfile
        } else {
            profiles.append(demoProfile)
        }
    }

    return profiles
}

func updatingRegisteredProfile(
    rawValue: String,
    accountID: String,
    phoneNumber: String,
    email: String?,
    password: String?,
    language: AppLanguage?
) -> String {
    var profiles = decodeRegisteredProfiles(from: rawValue)
    guard let index = profiles.firstIndex(where: {
        (!accountID.isEmpty && $0.accountID == accountID) ||
        (!phoneNumber.isEmpty && $0.phoneNumber == phoneNumber)
    }) else {
        return rawValue
    }

    if let email {
        profiles[index].email = email
    }
    if let password {
        profiles[index].password = password
    }
    if let language {
        profiles[index].language = language
    }

    return encodeRegisteredProfiles(profiles)
}

func generateUniqueAccountID(existingIDs: Set<String>) -> String {
    var candidate = ""
    repeat {
        candidate = String(Int.random(in: 100000...999999))
    } while existingIDs.contains(candidate)
    return candidate
}

func decodeSections(from rawValue: String) -> [ManagerSection] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [] }
    return (try? JSONDecoder().decode([ManagerSection].self, from: data)) ?? []
}

func encodeSections(_ sections: [ManagerSection]) -> String {
    guard let data = try? JSONEncoder().encode(sections),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func defaultDemoSections() -> [ManagerSection] {
    let parentSectionID = UUID()
    let foreman = SectionMember(
        accountID: "200001",
        name: "Jake Reynolds",
        phoneNumber: "4155551023",
        role: .foreman,
        isOnSite: true,
        todos: [
            MemberTodo(title: "Approve morning concrete pour checklist", dueDate: Date()),
            MemberTodo(title: "Review rebar delivery log", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        ]
    )
    let safetyLead = SectionMember(
        name: "Maya Chen",
        phoneNumber: "4155551944",
        role: .safety,
        isOnSite: true,
        todos: [
            MemberTodo(title: "Run 2PM harness inspection", dueDate: Date())
        ]
    )
    let crewLead = SectionMember(
        name: "Arjun Patel",
        phoneNumber: "4155552077",
        role: .lead,
        isOnSite: false
    )

    let parentSection = ManagerSection(
        id: parentSectionID,
        ownerAccountID: defaultManagerDemoProfile().accountID,
        name: "Tower A - Concrete",
        codeWord: "STEEL-GATE-482",
        members: [foreman, safetyLead, crewLead],
        groupChats: [
            SectionGroupChat(
                name: "Daily Coordination",
                createdAt: "3/09/26",
                participantMemberIDs: [foreman.id, safetyLead.id, crewLead.id],
                messages: [
                    GroupChatMessage(sender: "Foreman", text: "Pour starts at 10:30. Stage crews by 10:15.", time: "9:40 AM")
                ]
            ),
            SectionGroupChat(
                name: "Safety Alerts",
                createdAt: "3/09/26",
                participantMemberIDs: [safetyLead.id, foreman.id],
                messages: [
                    GroupChatMessage(sender: "Safety Lead", text: "EMERGENCY: Clear the east access ramp now. Crane swing zone breach reported. Move to the muster point immediately.", time: "8:05 AM")
                ]
            )
        ],
        sectionTasks: [
            SectionTask(
                title: "Finalize slab prep for afternoon pour",
                priority: .high,
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                assigneeIDs: [foreman.id, safetyLead.id],
                managerNotes: "Confirm rebar spacing and send photo update before 2 PM.",
                doneMemberIDs: [foreman.id],
                verifiedMemberIDs: [foreman.id]
            ),
            SectionTask(
                title: "Acknowledge east access pour barricades",
                descriptionText: "Walk the east access path, confirm barricades are staged, and mark the task done for crew lead verification.",
                priority: .urgent,
                dueDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
                siteName: "Tower A - Concrete",
                locationDetails: "East access ramp",
                checklistItems: [
                    TaskChecklistItem(title: "Barricades staged"),
                    TaskChecklistItem(title: "Access signage visible"),
                    TaskChecklistItem(title: "Crew brief completed")
                ],
                requiresAcknowledgement: true,
                assigneeIDs: [foreman.id],
                managerNotes: "Mark this done after you physically confirm the barricades. Crew Lead will verify final completion.",
                doneMemberIDs: [foreman.id],
                verifiedMemberIDs: []
            )
        ]
    )

    let demoSubsection = ManagerSection(
        ownerAccountID: defaultManagerDemoProfile().accountID,
        parentSectionID: parentSectionID,
        name: "Tower A - Concrete - Deck Prep",
        codeWord: "DECK-PREP-214",
        featureSettings: parentSection.featureSettings,
        members: [foreman, crewLead],
        groupChats: [
            SectionGroupChat(
                name: "Deck Prep Chat",
                createdAt: "3/10/26",
                participantMemberIDs: [foreman.id, crewLead.id],
                writableMemberIDs: [foreman.id, crewLead.id],
                messages: [
                    GroupChatMessage(sender: "Foreman", text: "Start layout on the east deck after the 8 AM briefing.", time: "7:35 AM"),
                    GroupChatMessage(sender: "Arjun P.", text: "Copy. We will stage material at the north access point.", time: "7:42 AM")
                ]
            )
        ],
        sectionTasks: [
            SectionTask(
                title: "Mark deck embed locations",
                priority: .medium,
                dueDate: Date(),
                assigneeIDs: [foreman.id, crewLead.id],
                managerNotes: "Complete before concrete inspection at noon."
            )
        ]
    )

    return [parentSection, demoSubsection]
}

func defaultLeadershipDemoSection() -> ManagerSection {
    let managerParticipant = SectionMember(
        accountID: defaultManagerDemoProfile().accountID,
        name: defaultManagerDemoProfile().name,
        phoneNumber: defaultManagerDemoProfile().phoneNumber,
        role: .foreman,
        isOnSite: true,
        todos: [
            MemberTodo(title: "Finalize today's steel erection sequencing plan", dueDate: Date()),
            MemberTodo(title: "Confirm inspection sign-off for level 3 deck placement", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        ]
    )
    let superintendent = SectionMember(
        accountID: "100101",
        name: "Rosa Alvarez",
        phoneNumber: "4155550110",
        role: .safety,
        isOnSite: true
    )

    return ManagerSection(
        ownerAccountID: "900001",
        name: "Campus Expansion - Steel",
        codeWord: "CRANE-DECK-219",
        members: [managerParticipant, superintendent],
        groupChats: [
            SectionGroupChat(
                name: "Superintendent Coordination",
                createdAt: "3/10/26",
                participantMemberIDs: [managerParticipant.id, superintendent.id],
                writableMemberIDs: [managerParticipant.id, superintendent.id],
                messages: [
                    GroupChatMessage(sender: "Boss", text: "Bob, lead the subcontractor coordination meeting before the 9 AM steel delivery.", time: "7:10 AM"),
                    GroupChatMessage(sender: "Rosa A.", text: "Safety walk is complete. Hoisting permit is cleared for the afternoon pick.", time: "7:28 AM")
                ]
            )
        ],
        sectionTasks: [
            SectionTask(
                title: "Coordinate steel delivery, crane window, and level 3 access plan",
                priority: .high,
                dueDate: Date(),
                assigneeIDs: [managerParticipant.id],
                managerNotes: "Confirm laydown yard routing, crane availability, and inspector timing before the noon production meeting."
            )
        ]
    )
}

func decodeStringArray(from rawValue: String) -> [String] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}

func encodeStringArray(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func mergedSectionsWithDemoSection(from rawValue: String) -> [ManagerSection] {
    var sections = decodeSections(from: rawValue)
    let baseDemoSections = defaultDemoSections()
    let demoParentCode = "STEEL-GATE-482"
    let storedDemoParentID = sections.first(where: { $0.codeWord == demoParentCode })?.id
    let demoSections = baseDemoSections.map { section in
        guard section.parentSectionID != nil, let storedDemoParentID else { return section }
        var updatedSection = section
        updatedSection.parentSectionID = storedDemoParentID
        return updatedSection
    } + [defaultLeadershipDemoSection()]

    if sections.isEmpty {
        return baseDemoSections + [defaultLeadershipDemoSection()]
    }

    for demoSection in demoSections {
        if let index = sections.firstIndex(where: { $0.codeWord == demoSection.codeWord }) {
            if sections[index].ownerAccountID == nil {
                sections[index].ownerAccountID = demoSection.ownerAccountID
            }
            if sections[index].parentSectionID == nil {
                sections[index].parentSectionID = demoSection.parentSectionID
            }
            sections[index] = syncedDemoSection(existing: sections[index], demo: demoSection)
            if sections[index].members.isEmpty {
                sections[index].members = demoSection.members
            }
            if sections[index].groupChats.isEmpty {
                sections[index].groupChats = demoSection.groupChats
            }
            if sections[index].sectionTasks.isEmpty {
                sections[index].sectionTasks = demoSection.sectionTasks
            }
        } else {
            sections.append(demoSection)
        }
    }

    return sections
}

private func syncedDemoSection(existing: ManagerSection, demo: ManagerSection) -> ManagerSection {
    var updated = existing
    var memberIDMap: [UUID: UUID] = [:]

    for demoMember in demo.members {
        if let memberIndex = updated.members.firstIndex(where: {
            (!demoMember.phoneNumber.isEmpty && $0.phoneNumber == demoMember.phoneNumber) ||
            (demoMember.accountID != nil && $0.accountID == demoMember.accountID)
        }) {
            memberIDMap[demoMember.id] = updated.members[memberIndex].id
            updated.members[memberIndex].name = demoMember.name
        }
    }

    let senderMap: [String: String] = [
        "J. Reynolds": "Jake R.",
        "Jake R.": "Jake R.",
        "Jake Reynolds": "Jake R.",
        "M. Chen": "Maya C.",
        "Maya C.": "Maya C.",
        "Maya Chen": "Maya C.",
        "A. Patel": "Arjun P.",
        "Arjun P.": "Arjun P.",
        "Arjun Patel": "Arjun P.",
        "R. Alvarez": "Rosa A.",
        "Rosa A.": "Rosa A.",
        "Rosa Alvarez": "Rosa A."
    ]

    for chatIndex in updated.groupChats.indices {
        for messageIndex in updated.groupChats[chatIndex].messages.indices {
            let currentSender = updated.groupChats[chatIndex].messages[messageIndex].sender
            if let replacement = senderMap[currentSender] {
                updated.groupChats[chatIndex].messages[messageIndex].sender = replacement
            }
        }
    }

    for demoTask in demo.sectionTasks where !updated.sectionTasks.contains(where: { $0.title == demoTask.title }) {
        var remappedTask = demoTask
        remappedTask.assigneeIDs = demoTask.assigneeIDs.map { memberIDMap[$0] ?? $0 }
        remappedTask.doneMemberIDs = demoTask.doneMemberIDs.map { memberIDMap[$0] ?? $0 }
        remappedTask.verifiedMemberIDs = demoTask.verifiedMemberIDs.map { memberIDMap[$0] ?? $0 }
        updated.sectionTasks.append(remappedTask)
    }

    return updated
}

func defaultLeadershipAssignedSectionCodes(for accountID: String) -> [String] {
    if accountID == defaultManagerDemoProfile().accountID {
        return [defaultLeadershipDemoSection().codeWord]
    }
    return []
}

func decodeWorkerPrivateNotes(_ rawValue: String) -> [String: String] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
}

func encodeWorkerPrivateNotes(_ notes: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(notes),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func decodeWorkerSavedMessages(_ rawValue: String) -> [String: [String]] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [:] }
    return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
}

func encodeWorkerSavedMessages(_ savedMessages: [String: [String]]) -> String {
    guard let data = try? JSONEncoder().encode(savedMessages),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func decodeMemberTodos(from rawValue: String) -> [MemberTodo] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [] }
    return (try? JSONDecoder().decode([MemberTodo].self, from: data)) ?? []
}

func encodeMemberTodos(_ todos: [MemberTodo]) -> String {
    guard let data = try? JSONEncoder().encode(todos),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func splitFullName(_ fullName: String) -> (firstName: String, lastName: String) {
    let parts = fullName
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: " ")
        .map(String.init)

    guard let first = parts.first else { return ("", "") }
    let last = parts.dropFirst().joined(separator: " ")
    return (first, last)
}

func combinedFullName(firstName: String, lastName: String) -> String {
    [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func abbreviatedDisplayName(_ fullName: String) -> String {
    let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return "" }
    let parts = name.split(separator: " ").map(String.init)
    guard let first = parts.first else { return name }
    guard let last = parts.dropFirst().first, let initial = last.first else { return first }
    return "\(first) \(initial)."
}

func decodeManagerCrewNicknames(from rawValue: String) -> [String: String] {
    guard let data = rawValue.data(using: .utf8), !rawValue.isEmpty else { return [:] }
    return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
}

func encodeManagerCrewNicknames(_ nicknames: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(nicknames),
          let json = String(data: data, encoding: .utf8) else {
        return ""
    }
    return json
}

func crewNicknameKey(accountID: String?, phoneNumber: String) -> String {
    if let accountID, !accountID.isEmpty {
        return "account:\(accountID)"
    }
    return "phone:\(phoneNumber)"
}

func managerDisplayName(for member: SectionMember, nicknames: [String: String]) -> String {
    let key = crewNicknameKey(accountID: member.accountID, phoneNumber: member.phoneNumber)
    let nickname = nicknames[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !nickname.isEmpty {
        return nickname
    }
    return abbreviatedDisplayName(member.name)
}

func localized(_ text: String, _ language: AppLanguage) -> String {
    if text == "Language" || text == "App Language" {
        return "Language/Idioma"
    }

    guard language == .spanish else { return text }

    let translations: [String: String] = [
        "Crew Lead": "Jefe de cuadrilla",
        "Worker": "Cuadrilla",
        "Crew": "Cuadrilla",
        "Open ARCVisor": "Abrir ARCVisor",
        "Welcome to": "Bienvenido a",
        "Demo Mode": "Modo demo",
        "Open Demo": "Abrir demo",
        "Exit Demo": "Salir del demo",
        "View As": "Ver como",
        "Try the seeded crew lead and crew experience without signing in.": "Prueba la experiencia preconfigurada de jefe de cuadrilla y cuadrilla sin iniciar sesión.",
        "Mode": "Modo",
        "Create Profile": "Crear perfil",
        "Sign In": "Iniciar sesión",
        "Full name": "Nombre completo",
        "First name": "Nombre",
        "Last name": "Apellido",
        "Nickname": "Apodo",
        "Save Nickname": "Guardar apodo",
        "Phone number": "Número de teléfono",
        "Create password": "Crear contraseña",
        "Email (optional)": "Correo (opcional)",
        "I am a": "Soy",
        "Section Access": "Acceso a sección",
        "Section code word": "Código de sección",
        "Password": "Contraseña",
        "No sections exist yet. Ask your crew lead to create one and share its code word.": "Todavía no hay secciones. Pídele a tu jefe de cuadrilla que cree una y comparta su código.",
        "Enter the section code word from your crew lead to join the right crew.": "Ingresa el código de sección de tu jefe de cuadrilla para unirte al equipo correcto.",
        "Sections": "Secciones",
        "Managed Sections": "Secciones administradas",
        "Leadership Sections": "Secciones de liderazgo",
        "Subsections": "Subsecciones",
        "No managed sections yet. Tap + to create one.": "Todavía no hay secciones administradas. Toca + para crear una.",
        "No subsections yet.": "Todavía no hay subsecciones.",
        "No leadership sections joined yet.": "Todavía no te has unido a secciones de liderazgo.",
        "Show Subsections": "Mostrar subsecciones",
        "Create Subsection": "Crear subsección",
        "New Subsection": "Nueva subsección",
        "Subsection name": "Nombre de la subsección",
        "Join Boss Section": "Unirse a la sección del jefe",
        "Join Section": "Unirse a la sección",
        "Boss": "Jefe",
        "Enter the section code word from leadership to join their section dashboard.": "Ingresa el código de sección de liderazgo para unirte a su panel de sección.",
        "You already manage this section.": "Ya administras esta sección.",
        "You're already in this leadership section.": "Ya estás en esta sección de liderazgo.",
        "No section found for that code word.": "No se encontró ninguna sección para ese código.",
        "Joined leadership section.": "Te uniste a la sección de liderazgo.",
        "My Profile": "Mi perfil",
        "Profile": "Perfil",
        "Role: Crew Lead": "Rol: Jefe de cuadrilla",
        "Role: Worker": "Rol: Cuadrilla",
        "Role: Crew": "Rol: Cuadrilla",
        "Account ID": "ID de cuenta",
        "Phone": "Teléfono",
        "Email": "Correo",
        "Email address": "Correo electrónico",
        "Save Email": "Guardar correo",
        "Language": "Idioma",
        "App Language": "Idioma de la app",
        "Save Language": "Guardar idioma",
        "Change Password": "Cambiar contraseña",
        "Current password": "Contraseña actual",
        "New password": "Nueva contraseña",
        "Confirm new password": "Confirmar nueva contraseña",
        "Update Password": "Actualizar contraseña",
        "Time Clock": "Reloj",
        "Shift: Day Shift": "Turno: Día",
        "Status: On Site": "Estado: En obra",
        "Status: Off Site": "Estado: Fuera de obra",
        "Clock In": "Entrada",
        "Clock Out": "Salida",
        "Clocked In": "Hora de entrada",
        "Clocked Out": "Hora de salida",
        "Assigned Tasks": "Tareas asignadas",
        "Saved Messages": "Mensajes guardados",
        "No saved messages yet.": "Todavía no hay mensajes guardados.",
        "Save Message": "Guardar mensaje",
        "Unsave Message": "Quitar mensaje guardado",
        "Waiting for crew lead verification": "Esperando verificación del jefe de cuadrilla",
        "Overall To-Do List": "Lista general de tareas",
        "Show Overall To-Do List": "Mostrar la lista general de tareas",
        "No leadership to-dos assigned yet.": "Todavía no hay tareas de liderazgo asignadas.",
        "My To-Do": "Mi tarea",
        "Personal To-Dos": "Tareas personales",
        "Section Task": "Tarea de sección",
        "Personal To-Do": "Tarea personal",
        "Chats": "Chats",
        "Read Only": "Solo lectura",
        "Section": "Sección",
        "Section Membership": "Membresía de sección",
        "Code Word": "Código",
        "From": "De",
        "Today": "Hoy",
        "No time clock activity recorded today.": "No hay actividad registrada hoy.",
        "Type a message": "Escribe un mensaje",
        "Send Media": "Enviar archivo",
        "Photo": "Foto",
        "Video": "Video",
        "Cancel": "Cancelar",
        "Notifications": "Notificaciones",
        "Alert Type": "Tipo de alerta",
        "Pinned Messages": "Mensajes fijados",
        "Members": "Miembros",
        "Show Members": "Mostrar miembros",
        "Can write in chat": "Puede escribir en el chat",
        "Read only": "Solo lectura",
        "Chat Details": "Detalles del chat",
        "This chat is read only. Your crew lead can enable write access in chat settings.": "Este chat es de solo lectura. Tu jefe de cuadrilla puede habilitar acceso de escritura en la configuración del chat.",
        "No workers have joined this section yet.": "Todavía no se han unido cuadrillas a esta sección.",
        "No crews have joined this section yet.": "Todavía no se han unido cuadrillas a esta sección.",
        "On Site": "En obra",
        "Off Site": "Fuera de obra",
        "Section tasks": "Tareas de la sección",
        "Personal to-dos": "Tareas personales",
        "Completed": "Completado",
        "Group Chats": "Chats grupales",
        "No group chats yet. Tap + to create one.": "Todavía no hay chats grupales. Toca + para crear uno.",
        "Section Tasks": "Tareas de la sección",
        "Assign Task": "Asignar tarea",
        "To Verify": "Por verificar",
        "No section tasks yet.": "Todavía no hay tareas de sección.",
        "Task View": "Vista de tareas",
        "Calendar": "Calendario",
        "No tasks on this date.": "No hay tareas en esta fecha.",
        "Week Of": "Semana de",
        "No tasks in this week.": "No hay tareas en esta semana.",
        "Section Details": "Detalles de la sección",
        "Section name": "Nombre de la sección",
        "Save Section Details": "Guardar detalles de la sección",
        "That code word is already being used by another section.": "Ese código ya está siendo usado por otra sección.",
        "Section details saved.": "Detalles de la sección guardados.",
        "Section Settings": "Configuración de la sección",
        "Section Features": "Funciones de la sección",
        "Enable Time Clock": "Activar reloj",
        "Enable Group Chats": "Activar chats grupales",
        "Enable Section Tasks": "Activar tareas de la sección",
        "Enable Personal To-Dos": "Activar tareas personales",
        "Enable Manual Member Add": "Activar agregar miembro manualmente",
        "Copy Code": "Copiar código",
        "Share Code": "Compartir código",
        "Account ID number": "Número de ID de cuenta",
        "Add Member by ID": "Agregar miembro por ID",
        "Add": "Agregar",
        "Add All": "Agregar a todos",
        "Manual member add is turned off in section settings.": "Agregar miembros manualmente está desactivado en la configuración de la sección.",
        "New Group Chat": "Nuevo chat grupal",
        "Group chat name": "Nombre del chat grupal",
        "Add Members": "Agregar miembros",
        "No members in parent section.": "No hay miembros en la sección principal.",
        "No additional parent section members available.": "No hay miembros adicionales disponibles de la sección principal.",
        "added from parent section.": "agregado desde la sección principal.",
        "No section members available yet.": "Todavía no hay miembros disponibles en la sección.",
        "Create Group Chat": "Crear chat grupal",
        "Task Details": "Detalles de la tarea",
        "Task title": "Título de la tarea",
        "Description": "Descripción",
        "Description (use keyboard or dictation)": "Descripción (usa teclado o dictado)",
        "Priority": "Prioridad",
        "Due Date": "Fecha de entrega",
        "Due Time": "Hora de entrega",
        "Site": "Obra",
        "Location": "Ubicación",
        "Location (optional)": "Ubicación (opcional)",
        "Checklist Items": "Lista de verificación",
        "Checklist item": "Elemento de la lista",
        "No checklist items yet.": "Todavía no hay elementos en la lista.",
        "Attachments": "Archivos adjuntos",
        "Add Attachment": "Agregar adjunto",
        "No attachments yet.": "Todavía no hay adjuntos.",
        "Requires acknowledgement": "Requiere confirmación",
        "Assign To": "Asignar a",
        "No section members available.": "No hay miembros disponibles en la sección.",
        "Create Task": "Crear tarea",
        "Task": "Tarea",
        "To-Do": "Tarea",
        "Status": "Estado",
        "Crew Lead Notes": "Notas del jefe de cuadrilla",
        "No crew lead notes yet.": "Todavía no hay notas del jefe de cuadrilla.",
        "My Private Notes": "Mis notas privadas",
        "Save Private Note": "Guardar nota privada",
        "Mark Complete": "Marcar como completada",
        "Mark Done": "Marcar como lista",
        "Save Task Updates": "Guardar cambios de tarea",
        "Completion Status": "Estado de finalización",
        "No members assigned to this task.": "No hay miembros asignados a esta tarea.",
        "Complete": "Completado",
        "Assigned": "Asignado",
        "Verified": "Verificado",
        "Verify": "Verificar",
        "Pending": "Pendiente",
        "To-Do Details": "Detalles de la tarea",
        "To-do title": "Título de la tarea",
        "Save To-Do Updates": "Guardar cambios de tarea",
        "Role & Status": "Rol y estado",
        "Role": "Rol",
        "Today's Time Clock": "Reloj de hoy",
        "Scheduled To-Dos": "Tareas programadas",
        "No to-dos assigned yet.": "Todavía no hay tareas asignadas.",
        "To-Do View": "Vista de tareas",
        "No to-dos on this date.": "No hay tareas en esta fecha.",
        "Delete": "Eliminar",
        "Assign To-Do on Calendar": "Asignar tarea en el calendario",
        "To-do item": "Tarea",
        "Crew Lead notes (optional)": "Notas del jefe de cuadrilla (opcional)",
        "Add To-Do": "Agregar tarea",
        "Due": "Entrega",
        "Remove Members": "Eliminar miembros",
        "Remove": "Eliminar",
        "No members in this section.": "No hay miembros en esta sección.",
        "No subsections assigned.": "No hay subsecciones asignadas.",
        "Done": "Listo",
        "Section not found.": "Sección no encontrada.",
        "Augmented Reality Construction Visor": "Visor de construcción de realidad aumentada",
        "Siri & Shortcuts": "Siri y Atajos",
        "Use Siri or the Shortcuts app to run ARCLink actions like adding a personal to-do.": "Usa Siri o la app Atajos para ejecutar acciones de ARCLink, como agregar una tarea personal.",
        "Signed in as": "Sesión iniciada como",
        "Connection": "Conexión",
        "Device discovery ready": "Detección de dispositivo lista",
        "Live section sync enabled": "Sincronización en vivo de la sección activada",
        "Live section sync unavailable": "Sincronización en vivo de la sección no disponible",
        "Task overlays available": "Superposiciones de tareas disponibles",
        "Task overlays unavailable": "Superposiciones de tareas no disponibles",
        "What ARCVisor Will Do": "Lo que hará ARCVisor",
        "Payload Preview": "Vista previa de carga",
        "Display Preview": "Vista previa de pantalla",
        "Outgoing Device Payload": "Carga saliente al dispositivo",
        "Copy JSON Payload": "Copiar carga JSON",
        "Payload copied to clipboard.": "Carga copiada al portapapeles.",
        "Review the live JSON currently being prepared for the Raspberry Pi.": "Revisa el JSON en vivo que se está preparando para la Raspberry Pi.",
        "Simple micro-OLED mock using the same live payload data.": "Maqueta simple de micro-OLED usando los mismos datos de carga en vivo.",
        "Payload unavailable.": "Carga no disponible.",
        "ARCVisor connects automatically when the device is available.": "ARCVisor se conecta automáticamente cuando el dispositivo está disponible.",
        "Show section tasks, crew locations, and pinned updates in an AR visor view.": "Mostrar tareas de la sección, ubicaciones del equipo y actualizaciones fijadas en una vista de visor AR.",
        "Pull worker assignments and on-site status directly from ARCLink.": "Obtener asignaciones de cuadrillas y estado en obra directamente desde ARCLink.",
        "Pull crew assignments and on-site status directly from ARCLink.": "Obtener asignaciones de cuadrillas y estado en obra directamente desde ARCLink.",
        "Support field walk-throughs, safety overlays, and visual markups.": "Permitir recorridos en campo, superposiciones de seguridad y anotaciones visuales.",
        "Connect ARCVisor": "Conectar ARCVisor",
        "Connection flow placeholder for demo. This button is the app entry point for the future visor pairing flow.": "Marcador de posición de conexión para la demo. Este botón es el punto de entrada de la app para el futuro flujo de vinculación del visor."
    ]

    return translations[text] ?? text
}

struct ARCVisorPayloadContext {
    let userName: String
    let roleTitle: String
    let profileAccountID: String
    let profilePhoneNumber: String
    let managerSectionsRaw: String
    let assignedSectionCodesRaw: String
    let managerPersonalTodosRaw: String
}

struct ARCVisorPayload: Codable {
    let userName: String
    let sectionSummaries: [ARCVisorSectionSummary]
    let topTodos: [ARCVisorTodoSummary]
    let notifications: [ARCVisorNotificationSummary]
}

struct ARCVisorSectionSummary: Codable {
    let name: String
    let codeWord: String
    let memberCount: Int
    let taskCount: Int
    let chatCount: Int
}

struct ARCVisorTodoSummary: Codable {
    let title: String
    let priority: String
    let sourceSection: String
    let dueDate: Date
}

struct ARCVisorNotificationSummary: Codable {
    let title: String
    let message: String
}

func encodedARCVisorPayload(from context: ARCVisorPayloadContext) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(arcVisorPayload(from: context))
    return String(decoding: data, as: UTF8.self)
}

func arcVisorPayload(from context: ARCVisorPayloadContext) -> ARCVisorPayload {
    ARCVisorPayload(
        userName: context.userName,
        sectionSummaries: arcVisorSectionSummaries(from: context),
        topTodos: arcVisorTopTodos(from: context),
        notifications: arcVisorNotifications(from: context)
    )
}

private func arcVisorSectionSummaries(from context: ARCVisorPayloadContext) -> [ARCVisorSectionSummary] {
    let allSections = decodeSections(from: context.managerSectionsRaw)
    let assignedLeadershipCodes = decodeStringArray(from: context.assignedSectionCodesRaw)

    if context.roleTitle == "Crew Lead" {
        return allSections
            .filter { $0.ownerAccountID == context.profileAccountID || assignedLeadershipCodes.contains($0.codeWord) }
            .map { section in
                ARCVisorSectionSummary(
                    name: section.name,
                    codeWord: section.codeWord,
                    memberCount: section.members.count,
                    taskCount: section.sectionTasks.count,
                    chatCount: section.groupChats.count
                )
            }
    }

    let crewSections = allSections.filter { section in
        section.members.contains(where: { $0.phoneNumber == context.profilePhoneNumber })
    }

    return crewSections.map { section in
        let member = section.members.first(where: { $0.phoneNumber == context.profilePhoneNumber })
        let assignedTaskCount = section.sectionTasks.filter { task in
            guard let member else { return false }
            return task.assigneeIDs.contains(member.id)
        }.count

        return ARCVisorSectionSummary(
            name: section.name,
            codeWord: section.codeWord,
            memberCount: section.members.count,
            taskCount: assignedTaskCount,
            chatCount: section.groupChats.filter { chat in
                guard let member else { return false }
                return chat.participantMemberIDs.isEmpty || chat.participantMemberIDs.contains(member.id)
            }.count
        )
    }
}

private func arcVisorTopTodos(from context: ARCVisorPayloadContext) -> [ARCVisorTodoSummary] {
    let todos = context.roleTitle == "Crew Lead"
        ? managerARCVisorTodos(from: context)
        : crewARCVisorTodos(from: context)

    return todos
        .sorted {
            let leftRank = priorityRank(for: $0.priority)
            let rightRank = priorityRank(for: $1.priority)
            if leftRank == rightRank {
                return $0.dueDate < $1.dueDate
            }
            return leftRank > rightRank
        }
        .prefix(3)
        .map { $0 }
}

private func arcVisorNotifications(from context: ARCVisorPayloadContext) -> [ARCVisorNotificationSummary] {
    let allSections = decodeSections(from: context.managerSectionsRaw)
    let assignedLeadershipCodes = decodeStringArray(from: context.assignedSectionCodesRaw)
    let sections: [ManagerSection]

    if context.roleTitle == "Crew Lead" {
        sections = allSections.filter {
            $0.ownerAccountID == context.profileAccountID || assignedLeadershipCodes.contains($0.codeWord)
        }
    } else {
        sections = allSections.filter { section in
            section.members.contains(where: { $0.phoneNumber == context.profilePhoneNumber })
        }
    }

    var notifications: [ARCVisorNotificationSummary] = []
    for section in sections {
        let currentMember = section.members.first(where: { $0.phoneNumber == context.profilePhoneNumber })
        let visibleChats = context.roleTitle == "Crew Lead"
            ? section.groupChats
            : section.groupChats.filter { chat in
                guard let currentMember else { return false }
                return chat.participantMemberIDs.isEmpty || chat.participantMemberIDs.contains(currentMember.id)
            }

        for chat in visibleChats {
            if let latestMessage = chat.messages.last {
                notifications.append(
                    ARCVisorNotificationSummary(
                        title: chat.name,
                        message: "\(latestMessage.sender): \(arcVisorMessagePreview(latestMessage))"
                    )
                )
            }
        }
    }

    if let emergencyNotification = notifications.last(where: {
        $0.message.localizedCaseInsensitiveContains("emergency")
    }) {
        let recentNonEmergencyNotifications = notifications
            .filter { $0.message != emergencyNotification.message || $0.title != emergencyNotification.title }
            .suffix(1)
        return [emergencyNotification] + recentNonEmergencyNotifications
    }

    return Array(notifications.suffix(2))
}

private func managerARCVisorTodos(from context: ARCVisorPayloadContext) -> [ARCVisorTodoSummary] {
    let allSections = decodeSections(from: context.managerSectionsRaw)
    let assignedLeadershipCodes = decodeStringArray(from: context.assignedSectionCodesRaw)

    var todos = decodeMemberTodos(from: context.managerPersonalTodosRaw).map { todo in
        ARCVisorTodoSummary(
            title: todo.title,
            priority: todo.priority.title,
            sourceSection: "My To-Do",
            dueDate: todo.dueDate
        )
    }

    let visibleSections = allSections.filter {
        $0.ownerAccountID == context.profileAccountID || assignedLeadershipCodes.contains($0.codeWord)
    }

    for section in visibleSections {
        guard let member = section.members.first(where: {
            (!context.profileAccountID.isEmpty && $0.accountID == context.profileAccountID) || $0.phoneNumber == context.profilePhoneNumber
        }) else { continue }

        todos.append(contentsOf: section.sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .map { task in
                ARCVisorTodoSummary(
                    title: task.title,
                    priority: task.priority.title,
                    sourceSection: section.name,
                    dueDate: task.dueDate
                )
            })

        todos.append(contentsOf: member.todos.map { todo in
            ARCVisorTodoSummary(
                title: todo.title,
                priority: todo.priority.title,
                sourceSection: section.name,
                dueDate: todo.dueDate
            )
        })
    }

    return todos
}

private func crewARCVisorTodos(from context: ARCVisorPayloadContext) -> [ARCVisorTodoSummary] {
    let allSections = decodeSections(from: context.managerSectionsRaw)
    let crewSections = allSections.filter { section in
        section.members.contains(where: { $0.phoneNumber == context.profilePhoneNumber })
    }

    var todos: [ARCVisorTodoSummary] = []
    for section in crewSections {
        guard let member = section.members.first(where: { $0.phoneNumber == context.profilePhoneNumber }) else { continue }

        todos.append(contentsOf: section.sectionTasks
            .filter { $0.assigneeIDs.contains(member.id) }
            .map { task in
                ARCVisorTodoSummary(
                    title: task.title,
                    priority: task.priority.title,
                    sourceSection: section.name,
                    dueDate: task.dueDate
                )
            })

        todos.append(contentsOf: member.todos.map { todo in
            ARCVisorTodoSummary(
                title: todo.title,
                priority: todo.priority.title,
                sourceSection: section.name,
                dueDate: todo.dueDate
            )
        })
    }

    return todos
}

private func priorityRank(for priority: String) -> Int {
    switch priority {
    case TaskPriority.urgent.title:
        return 4
    case TaskPriority.high.title:
        return 3
    case TaskPriority.medium.title:
        return 2
    default:
        return 1
    }
}

private func arcVisorMessagePreview(_ message: GroupChatMessage) -> String {
    switch message.messageType {
    case .text:
        return message.text
    case .photo:
        return message.attachmentLabel ?? "Photo"
    case .video:
        return message.attachmentLabel ?? "Video"
    }
}

func greetingText(name: String, language: AppLanguage) -> String {
    language == .spanish ? "Hola, \(name)!" : "Hi, \(name)!"
}

func normalizeCodeWord(_ input: String) -> String {
    input
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
}

func randomSiteCodeWord(existingCodes: Set<String>) -> String {
    let adjectives = ["STEEL", "BRICK", "CRANE", "SAFETY", "BEAM", "CONCRETE"]
    let nouns = ["GATE", "TOWER", "SLAB", "ANCHOR", "RIG", "LEVEL"]
    var codeWord = ""

    repeat {
        let adjective = adjectives.randomElement() ?? "SITE"
        let noun = nouns.randomElement() ?? "CODE"
        let number = Int.random(in: 100...999)
        codeWord = "\(adjective)-\(noun)-\(number)"
    } while existingCodes.contains(codeWord)

    return codeWord
}

func startOfWeek(for date: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: components) ?? date
}

struct EventCalendarView: View {
    @Binding var selectedDate: Date
    let highlightedDates: [Date]
    let language: AppLanguage

    @State private var displayedMonth = Date()

    private let calendar = Calendar.current

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth).capitalized
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .spanish ? "es_ES" : "en_US")
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.veryShortWeekdaySymbols ?? []
        let startIndex = max(calendar.firstWeekday - 1, 0)
        guard !symbols.isEmpty else { return [] }
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var highlightedDaySet: Set<Date> {
        Set(highlightedDates.map { calendar.startOfDay(for: $0) })
    }

    private var days: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDayOfMonth) else {
            return []
        }

        var dates: [CalendarDay] = []
        var currentDate = firstWeek.start
        while currentDate < lastWeek.end {
            dates.append(
                CalendarDay(
                    date: currentDate,
                    isCurrentMonth: calendar.isDate(currentDate, equalTo: displayedMonth, toGranularity: .month),
                    isSelected: calendar.isDate(currentDate, inSameDayAs: selectedDate),
                    hasEvent: highlightedDaySet.contains(calendar.startOfDay(for: currentDate))
                )
            )
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            if dates.count > 42 { break }
        }
        return dates
    }

    private var dayRows: [[CalendarDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(dayRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { day in
                            VStack(spacing: 4) {
                                Text(dayNumber(day.date))
                                    .font(.subheadline.weight(day.isSelected ? .semibold : .regular))
                                    .foregroundStyle(dayTextColor(for: day))
                                    .frame(width: 32, height: 32)
                                    .background(dayBackground(for: day))

                                Circle()
                                    .fill(day.hasEvent && day.isCurrentMonth ? Color.accentColor : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedDate = day.date
                                displayedMonth = day.date
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            displayedMonth = selectedDate
        }
        .onChange(of: selectedDate) { newValue in
            if !calendar.isDate(newValue, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newValue
            }
        }
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func dayTextColor(for day: CalendarDay) -> Color {
        if day.isSelected {
            return .white
        }
        return day.isCurrentMonth ? .primary : .secondary.opacity(0.5)
    }

    @ViewBuilder
    private func dayBackground(for day: CalendarDay) -> some View {
        if day.isSelected {
            Circle().fill(Color.accentColor)
        } else {
            Circle().fill(Color.clear)
        }
    }

    private struct CalendarDay: Identifiable {
        let date: Date
        let isCurrentMonth: Bool
        let isSelected: Bool
        let hasEvent: Bool

        var id: Date { date }
    }
}

func shortDateString() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    return formatter.string(from: Date())
}

func shortTimeString() -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: Date())
}

struct MediaPicker: UIViewControllerRepresentable {
    let mediaType: ChatMessageType
    let onPicked: (ChatMessageType, String) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator

        switch mediaType {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
        case .text:
            picker.mediaTypes = [UTType.image.identifier]
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaPicker

        init(parent: MediaPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            let label: String

            if let mediaURL = info[.mediaURL] as? URL {
                label = mediaURL.lastPathComponent
            } else {
                label = parent.mediaType == .photo ? "Photo \(shortTimeString())" : "Video \(shortTimeString())"
            }

            parent.onPicked(parent.mediaType, label)
            parent.dismiss()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
struct AppBrandImage: View {
    var helmetSize: CGFloat = 40
    var craneSize: CGFloat = 30
    var spacing: CGFloat = 4
    @Environment(\.colorScheme) private var colorScheme

    private var primaryLogoColor: Color {
        .arcAccentOrange
    }

    private var secondaryLogoColor: Color {
        .arcAccentOrange
    }

    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: "helmet.fill")
                .font(.system(size: helmetSize, weight: .bold))
                .foregroundStyle(primaryLogoColor)

            Image(systemName: "crane.fill")
                .font(.system(size: craneSize, weight: .semibold))
                .foregroundStyle(secondaryLogoColor)
        }
        .accessibilityHidden(true)
    }
}

struct AddPersonalTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Personal To-Do"
    static let description = IntentDescription("Adds a new personal to-do for the current Crew Lead account.")
    static let openAppWhenRun = false

    @Parameter(title: "Title")
    var titleText: String

    @Parameter(title: "Due Date")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$titleText) to personal to-dos")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return .result(dialog: "The to-do title can't be empty.")
        }

        let defaults = arcLinkActiveUserDefaults()
        let roleRawValue = defaults.string(forKey: "profileRole") ?? AppRole.manager.rawValue
        guard AppRole(rawValue: roleRawValue) == .manager else {
            return .result(dialog: "This shortcut is only available for the Crew Lead role.")
        }

        var todos = decodeMemberTodos(from: defaults.string(forKey: "managerPersonalTodosJSON") ?? "")
        todos.insert(
            MemberTodo(
                title: trimmedTitle,
                dueDate: dueDate ?? Date()
            ),
            at: 0
        )
        defaults.set(encodeMemberTodos(todos), forKey: "managerPersonalTodosJSON")

        return .result(dialog: IntentDialog("Added \(trimmedTitle) to your personal to-dos."))
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Marks one of the current user's tasks complete in ARCLink.")
    static let openAppWhenRun = false

    @Parameter(title: "Task Title")
    var taskTitle: String

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$taskTitle) complete")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return .result(dialog: "The task title can't be empty.")
        }

        let defaults = arcLinkActiveUserDefaults()
        switch markCurrentUserTaskComplete(named: trimmedTitle, defaults: defaults) {
        case .completed(let resolvedTitle):
            return .result(dialog: IntentDialog("Marked \(resolvedTitle) complete."))
        case .alreadyCompleted(let resolvedTitle):
            return .result(dialog: IntentDialog("\(resolvedTitle) is already marked complete."))
        case .notFound:
            return .result(dialog: IntentDialog("I couldn't find an existing task with that title for the current account."))
        }
    }
}

struct ReadMyTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Read My Tasks"
    static let description = IntentDescription("Reads the current user's assigned tasks from ARC Link.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: currentUserTasksDialog(defaults: arcLinkActiveUserDefaults()))
    }
}

struct AssignTaskToCrewMemberIntent: AppIntent {
    static let title: LocalizedStringResource = "Create and Assign Task"
    static let description = IntentDescription("Creates a section task and assigns it to a crew member for the current Crew Lead account.")
    static let openAppWhenRun = false

    @Parameter(title: "New Task Title")
    var taskTitle: String

    @Parameter(title: "Crew Member")
    var crewMemberName: String

    @Parameter(title: "Due Date")
    var dueDate: Date?

    @Parameter(title: "Section Name")
    var sectionName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$taskTitle) for \(\.$crewMemberName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanedTaskTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCrewMemberName = crewMemberName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTaskTitle.isEmpty else {
            return .result(dialog: "The task title can't be empty.")
        }
        guard !cleanedCrewMemberName.isEmpty else {
            return .result(dialog: "The crew member name can't be empty.")
        }

        let defaults = arcLinkActiveUserDefaults()
        guard let statusMessage = assignTaskToCrewMember(
            title: cleanedTaskTitle,
            crewMemberName: cleanedCrewMemberName,
            dueDate: dueDate,
            sectionName: sectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
            defaults: defaults
        ) else {
            return .result(dialog: "I couldn't find that crew member in your sections. This shortcut creates a new task and assigns it.")
        }

        return .result(dialog: IntentDialog(stringLiteral: statusMessage))
    }
}

struct ARCLinkShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddPersonalTodoIntent(),
            phrases: [
                "Add a personal to-do with \(.applicationName)",
                "Create a personal to-do with \(.applicationName)",
                "Add a to-do with \(.applicationName)"
            ],
            shortTitle: "Add To-Do",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Mark an existing task complete with \(.applicationName)",
                "Finish an existing task with \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ReadMyTasksIntent(),
            phrases: [
                "Read my tasks with \(.applicationName)",
                "What are my tasks with \(.applicationName)",
                "Show my tasks with \(.applicationName)"
            ],
            shortTitle: "Read My Tasks",
            systemImageName: "list.bullet.clipboard"
        )
        AppShortcut(
            intent: AssignTaskToCrewMemberIntent(),
            phrases: [
                "Dispatch crew work with \(.applicationName)",
                "Send a work order with \(.applicationName)",
                "Assign crew work with \(.applicationName)"
            ],
            shortTitle: "Dispatch Work",
            systemImageName: "person.badge.plus"
        )
        
        AppShortcut(
            intent: TranslateToSpanishIntent(),
            phrases: [
                "Translate to Spanish with \(.applicationName)",
                "Translate with \(.applicationName)",
                "Speak Spanish with \(.applicationName)",
                "Help me say something in Spanish with \(.applicationName)"
            ],
            shortTitle: "Translate to Spanish",
            systemImageName: "character.bubble"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .orange
    }
}
