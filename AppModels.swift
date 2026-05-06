//
//  AppModels.swift
//  test
//

import SwiftUI

enum AppRole: String, CaseIterable, Identifiable, Codable {
    case manager
    case worker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manager:
            return "Crew Lead"
        case .worker:
            return "Crew"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english
    case spanish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english:
            return "English"
        case .spanish:
            return "Spanish"
        }
    }
}

enum AuthTab: String, CaseIterable, Identifiable {
    case createProfile
    case signIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createProfile:
            return "Create Profile"
        case .signIn:
            return "Sign In"
        }
    }
}

struct AirQualityReading {
    let battery: Double?
    let carbon: Double?
    let temperature: Double?
    let humidity: Double?
    let rawValues: [String: String]

    var hasAnyReading: Bool {
        battery != nil || carbon != nil || temperature != nil || humidity != nil
    }
}

func decodeAirQualityReading(from rawJSONString: String) -> AirQualityReading? {
    guard let data = rawJSONString.data(using: .utf8),
          let jsonObject = try? JSONSerialization.jsonObject(with: data),
          let dictionary = jsonObject as? [String: Any] else {
        return nil
    }

    func value(forKeys keys: [String]) -> Double? {
        for key in keys {
            guard let rawValue = dictionary[key] else { continue }
            if let number = rawValue as? NSNumber {
                return number.doubleValue
            }
            if let string = rawValue as? String,
               let number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return number
            }
        }
        return nil
    }

    let normalizedRawValues = dictionary.reduce(into: [String: String]()) { partialResult, entry in
        partialResult[entry.key] = String(describing: entry.value)
    }

    return AirQualityReading(
        battery: value(forKeys: ["battery", "batteryLevel", "battery_level"]),
        carbon: value(forKeys: ["carbon", "co2", "carbonDioxide", "carbon_dioxide"]),
        temperature: value(forKeys: ["temperature", "temp"]),
        humidity: value(forKeys: ["humidity", "hum"]),
        rawValues: normalizedRawValues
    )
}

struct ManagerSection: Identifiable, Codable {
    let id: UUID
    var ownerAccountID: String?
    var parentSectionID: UUID?
    var name: String
    var codeWord: String
    var featureSettings: SectionFeatureSettings
    var members: [SectionMember]
    var groupChats: [SectionGroupChat]
    var sectionTasks: [SectionTask]

    init(
        id: UUID = UUID(),
        ownerAccountID: String? = nil,
        parentSectionID: UUID? = nil,
        name: String,
        codeWord: String,
        featureSettings: SectionFeatureSettings = SectionFeatureSettings(),
        members: [SectionMember] = [],
        groupChats: [SectionGroupChat] = [],
        sectionTasks: [SectionTask] = []
    ) {
        self.id = id
        self.ownerAccountID = ownerAccountID
        self.parentSectionID = parentSectionID
        self.name = name
        self.codeWord = codeWord
        self.featureSettings = featureSettings
        self.members = members
        self.groupChats = groupChats
        self.sectionTasks = sectionTasks
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerAccountID
        case parentSectionID
        case name
        case codeWord
        case featureSettings
        case members
        case groupChats
        case sectionTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ownerAccountID = try container.decodeIfPresent(String.self, forKey: .ownerAccountID)
        parentSectionID = try container.decodeIfPresent(UUID.self, forKey: .parentSectionID)
        name = try container.decode(String.self, forKey: .name)
        codeWord = try container.decode(String.self, forKey: .codeWord)
        featureSettings = try container.decodeIfPresent(SectionFeatureSettings.self, forKey: .featureSettings) ?? SectionFeatureSettings()
        members = try container.decodeIfPresent([SectionMember].self, forKey: .members) ?? []
        groupChats = try container.decodeIfPresent([SectionGroupChat].self, forKey: .groupChats) ?? []
        sectionTasks = try container.decodeIfPresent([SectionTask].self, forKey: .sectionTasks) ?? []
    }
}

struct SectionFeatureSettings: Codable {
    var timeClockEnabled: Bool
    var groupChatsEnabled: Bool
    var sectionTasksEnabled: Bool
    var personalTodosEnabled: Bool
    var manualMemberAddEnabled: Bool

    init(
        timeClockEnabled: Bool = true,
        groupChatsEnabled: Bool = true,
        sectionTasksEnabled: Bool = true,
        personalTodosEnabled: Bool = true,
        manualMemberAddEnabled: Bool = true
    ) {
        self.timeClockEnabled = timeClockEnabled
        self.groupChatsEnabled = groupChatsEnabled
        self.sectionTasksEnabled = sectionTasksEnabled
        self.personalTodosEnabled = personalTodosEnabled
        self.manualMemberAddEnabled = manualMemberAddEnabled
    }

    enum CodingKeys: String, CodingKey {
        case timeClockEnabled
        case groupChatsEnabled
        case sectionTasksEnabled
        case personalTodosEnabled
        case manualMemberAddEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeClockEnabled = try container.decodeIfPresent(Bool.self, forKey: .timeClockEnabled) ?? true
        groupChatsEnabled = try container.decodeIfPresent(Bool.self, forKey: .groupChatsEnabled) ?? true
        sectionTasksEnabled = try container.decodeIfPresent(Bool.self, forKey: .sectionTasksEnabled) ?? true
        personalTodosEnabled = try container.decodeIfPresent(Bool.self, forKey: .personalTodosEnabled) ?? true
        manualMemberAddEnabled = try container.decodeIfPresent(Bool.self, forKey: .manualMemberAddEnabled) ?? true
    }
}

struct SectionMember: Identifiable, Codable {
    let id: UUID
    var accountID: String?
    var name: String
    var phoneNumber: String
    var role: MemberRole
    var isOnSite: Bool
    var clockInTime: Date?
    var clockOutTime: Date?
    var todos: [MemberTodo]

    init(
        id: UUID = UUID(),
        accountID: String? = nil,
        name: String,
        phoneNumber: String,
        role: MemberRole = .worker,
        isOnSite: Bool = false,
        clockInTime: Date? = nil,
        clockOutTime: Date? = nil,
        todos: [MemberTodo] = []
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.phoneNumber = phoneNumber
        self.role = role
        self.isOnSite = isOnSite
        self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime
        self.todos = todos
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID
        case name
        case phoneNumber
        case role
        case isOnSite
        case clockInTime
        case clockOutTime
        case todos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        accountID = try container.decodeIfPresent(String.self, forKey: .accountID)
        name = try container.decode(String.self, forKey: .name)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        role = try container.decodeIfPresent(MemberRole.self, forKey: .role) ?? .worker
        isOnSite = try container.decodeIfPresent(Bool.self, forKey: .isOnSite) ?? false
        clockInTime = try container.decodeIfPresent(Date.self, forKey: .clockInTime)
        clockOutTime = try container.decodeIfPresent(Date.self, forKey: .clockOutTime)
        todos = try container.decodeIfPresent([MemberTodo].self, forKey: .todos) ?? []
    }
}

struct SectionGroupChat: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: String
    var participantMemberIDs: [UUID]
    var writableMemberIDs: [UUID]
    var notificationSetting: ChatNotificationSetting
    var pinnedMessageIDs: [UUID]
    var messages: [GroupChatMessage]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: String,
        participantMemberIDs: [UUID] = [],
        writableMemberIDs: [UUID] = [],
        notificationSetting: ChatNotificationSetting = .allMessages,
        pinnedMessageIDs: [UUID] = [],
        messages: [GroupChatMessage] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.participantMemberIDs = participantMemberIDs
        self.writableMemberIDs = writableMemberIDs.isEmpty ? participantMemberIDs : writableMemberIDs
        self.notificationSetting = notificationSetting
        self.pinnedMessageIDs = pinnedMessageIDs
        self.messages = messages
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case participantMemberIDs
        case writableMemberIDs
        case notificationSetting
        case pinnedMessageIDs
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        participantMemberIDs = try container.decodeIfPresent([UUID].self, forKey: .participantMemberIDs) ?? []
        writableMemberIDs = try container.decodeIfPresent([UUID].self, forKey: .writableMemberIDs) ?? participantMemberIDs
        notificationSetting = try container.decodeIfPresent(ChatNotificationSetting.self, forKey: .notificationSetting) ?? .allMessages
        pinnedMessageIDs = try container.decodeIfPresent([UUID].self, forKey: .pinnedMessageIDs) ?? []
        messages = try container.decodeIfPresent([GroupChatMessage].self, forKey: .messages) ?? []
    }
}

enum ChatNotificationSetting: String, CaseIterable, Codable, Identifiable {
    case allMessages
    case mentionsOnly
    case muted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allMessages:
            return "All Messages"
        case .mentionsOnly:
            return "Mentions Only"
        case .muted:
            return "Muted"
        }
    }
}

enum ChatMessageType: String, Codable {
    case text
    case photo
    case video
}

enum ChatReaction: String, CaseIterable, Identifiable {
    case thumbsUp = "👍"
    case heart = "❤️"
    case laugh = "😂"
    case warning = "⚠️"
    case check = "✅"

    var id: String { rawValue }
}

struct GroupChatMessage: Identifiable, Codable {
    let id: UUID
    var sender: String
    var text: String
    var time: String
    var messageType: ChatMessageType
    var attachmentLabel: String?
    var reactions: [MessageReaction]

    init(
        id: UUID = UUID(),
        sender: String,
        text: String,
        time: String,
        messageType: ChatMessageType = .text,
        attachmentLabel: String? = nil,
        reactions: [MessageReaction] = []
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.time = time
        self.messageType = messageType
        self.attachmentLabel = attachmentLabel
        self.reactions = reactions
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sender
        case text
        case time
        case messageType
        case attachmentLabel
        case reactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sender = try container.decode(String.self, forKey: .sender)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
        messageType = try container.decodeIfPresent(ChatMessageType.self, forKey: .messageType) ?? .text
        attachmentLabel = try container.decodeIfPresent(String.self, forKey: .attachmentLabel)
        reactions = try container.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
    }
}

struct MessageReaction: Identifiable, Codable {
    let id: UUID
    var emoji: String
    var by: String

    init(id: UUID = UUID(), emoji: String, by: String) {
        self.id = id
        self.emoji = emoji
        self.by = by
    }
}

struct SectionTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var descriptionText: String
    var priority: TaskPriority
    var dueDate: Date
    var siteName: String
    var locationDetails: String
    var checklistItems: [TaskChecklistItem]
    var attachments: [TaskAttachment]
    var requiresAcknowledgement: Bool
    var assigneeIDs: [UUID]
    var managerNotes: String
    var doneMemberIDs: [UUID]
    var verifiedMemberIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        descriptionText: String = "",
        priority: TaskPriority,
        dueDate: Date,
        siteName: String = "",
        locationDetails: String = "",
        checklistItems: [TaskChecklistItem] = [],
        attachments: [TaskAttachment] = [],
        requiresAcknowledgement: Bool = false,
        assigneeIDs: [UUID],
        managerNotes: String = "",
        doneMemberIDs: [UUID] = [],
        verifiedMemberIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.priority = priority
        self.dueDate = dueDate
        self.siteName = siteName
        self.locationDetails = locationDetails
        self.checklistItems = checklistItems
        self.attachments = attachments
        self.requiresAcknowledgement = requiresAcknowledgement
        self.assigneeIDs = assigneeIDs
        self.managerNotes = managerNotes
        self.doneMemberIDs = doneMemberIDs
        self.verifiedMemberIDs = verifiedMemberIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case descriptionText
        case priority
        case dueDate
        case siteName
        case locationDetails
        case checklistItems
        case attachments
        case requiresAcknowledgement
        case assigneeIDs
        case managerNotes
        case doneMemberIDs
        case verifiedMemberIDs
        case completedMemberIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        priority = try container.decode(TaskPriority.self, forKey: .priority)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName) ?? ""
        locationDetails = try container.decodeIfPresent(String.self, forKey: .locationDetails) ?? ""
        checklistItems = try container.decodeIfPresent([TaskChecklistItem].self, forKey: .checklistItems) ?? []
        attachments = try container.decodeIfPresent([TaskAttachment].self, forKey: .attachments) ?? []
        requiresAcknowledgement = try container.decodeIfPresent(Bool.self, forKey: .requiresAcknowledgement) ?? false
        assigneeIDs = try container.decodeIfPresent([UUID].self, forKey: .assigneeIDs) ?? []
        managerNotes = try container.decodeIfPresent(String.self, forKey: .managerNotes) ?? ""
        let legacyCompletedMemberIDs = try container.decodeIfPresent([UUID].self, forKey: .completedMemberIDs) ?? []
        doneMemberIDs = try container.decodeIfPresent([UUID].self, forKey: .doneMemberIDs) ?? legacyCompletedMemberIDs
        verifiedMemberIDs = try container.decodeIfPresent([UUID].self, forKey: .verifiedMemberIDs) ?? legacyCompletedMemberIDs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(descriptionText, forKey: .descriptionText)
        try container.encode(priority, forKey: .priority)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(siteName, forKey: .siteName)
        try container.encode(locationDetails, forKey: .locationDetails)
        try container.encode(checklistItems, forKey: .checklistItems)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(requiresAcknowledgement, forKey: .requiresAcknowledgement)
        try container.encode(assigneeIDs, forKey: .assigneeIDs)
        try container.encode(managerNotes, forKey: .managerNotes)
        try container.encode(doneMemberIDs, forKey: .doneMemberIDs)
        try container.encode(verifiedMemberIDs, forKey: .verifiedMemberIDs)
    }
}

struct TaskChecklistItem: Identifiable, Codable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}

struct TaskAttachment: Identifiable, Codable {
    let id: UUID
    var type: TaskAttachmentType
    var label: String
    var imageDataBase64: String?

    init(id: UUID = UUID(), type: TaskAttachmentType, label: String, imageDataBase64: String? = nil) {
        self.id = id
        self.type = type
        self.label = label
        self.imageDataBase64 = imageDataBase64
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case label
        case imageDataBase64
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(TaskAttachmentType.self, forKey: .type)
        label = try container.decode(String.self, forKey: .label)
        imageDataBase64 = try container.decodeIfPresent(String.self, forKey: .imageDataBase64)
    }
}

enum TaskAttachmentType: String, Codable, CaseIterable, Identifiable {
    case photo
    case video
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo:
            return "Photo"
        case .video:
            return "Video"
        case .pdf:
            return "PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .photo:
            return "photo"
        case .video:
            return "video"
        case .pdf:
            return "doc.richtext"
        }
    }
}

enum TaskTimelineView: String, CaseIterable, Identifiable {
    case calendar
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Calendar"
        case .week:
            return "Week"
        }
    }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .urgent:
            return "Urgent"
        }
    }

    var color: Color {
        switch self {
        case .low:
            return .gray
        case .medium:
            return .blue
        case .high:
            return .orange
        case .urgent:
            return .red
        }
    }
}

enum MemberRole: String, CaseIterable, Codable, Identifiable {
    case worker
    case lead
    case foreman
    case safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worker:
            return "Crew"
        case .lead:
            return "Lead"
        case .foreman:
            return "Foreman"
        case .safety:
            return "Safety"
        }
    }
}

struct MemberTodo: Identifiable, Codable {
    let id: UUID
    var title: String
    var descriptionText: String
    var dueDate: Date
    var priority: TaskPriority
    var siteName: String
    var locationDetails: String
    var checklistItems: [TaskChecklistItem]
    var attachments: [TaskAttachment]
    var requiresAcknowledgement: Bool
    var managerNotes: String
    var isMarkedDone: Bool
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        descriptionText: String = "",
        dueDate: Date,
        priority: TaskPriority = .medium,
        siteName: String = "",
        locationDetails: String = "",
        checklistItems: [TaskChecklistItem] = [],
        attachments: [TaskAttachment] = [],
        requiresAcknowledgement: Bool = false,
        managerNotes: String = "",
        isMarkedDone: Bool = false,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.descriptionText = descriptionText
        self.dueDate = dueDate
        self.priority = priority
        self.siteName = siteName
        self.locationDetails = locationDetails
        self.checklistItems = checklistItems
        self.attachments = attachments
        self.requiresAcknowledgement = requiresAcknowledgement
        self.managerNotes = managerNotes
        self.isMarkedDone = isMarkedDone
        self.isCompleted = isCompleted
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case descriptionText
        case dueDate
        case priority
        case siteName
        case locationDetails
        case checklistItems
        case attachments
        case requiresAcknowledgement
        case managerNotes
        case isMarkedDone
        case isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName) ?? ""
        locationDetails = try container.decodeIfPresent(String.self, forKey: .locationDetails) ?? ""
        checklistItems = try container.decodeIfPresent([TaskChecklistItem].self, forKey: .checklistItems) ?? []
        attachments = try container.decodeIfPresent([TaskAttachment].self, forKey: .attachments) ?? []
        requiresAcknowledgement = try container.decodeIfPresent(Bool.self, forKey: .requiresAcknowledgement) ?? false
        managerNotes = try container.decodeIfPresent(String.self, forKey: .managerNotes) ?? ""
        let legacyCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isMarkedDone = try container.decodeIfPresent(Bool.self, forKey: .isMarkedDone) ?? legacyCompleted
        isCompleted = legacyCompleted
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(descriptionText, forKey: .descriptionText)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(siteName, forKey: .siteName)
        try container.encode(locationDetails, forKey: .locationDetails)
        try container.encode(checklistItems, forKey: .checklistItems)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(requiresAcknowledgement, forKey: .requiresAcknowledgement)
        try container.encode(managerNotes, forKey: .managerNotes)
        try container.encode(isMarkedDone, forKey: .isMarkedDone)
        try container.encode(isCompleted, forKey: .isCompleted)
    }
}

struct CrewMessage: Identifiable {
    let id = UUID()
    let sender: String
    let text: String
    let time: String
}

struct ARCVisorBluetoothManager {
    enum ConnectionState {
        case idle
        case scanning
        case discovering
        case connecting
        case connected
        case failed
        case bluetoothUnavailable
    }

    var connectionState: ConnectionState = .idle
    var latestPayload = ""

    var isConnected: Bool {
        connectionState == .connected
    }

    var liveSectionSyncEnabled: Bool {
        isConnected
    }

    var taskOverlaysAvailable: Bool {
        isConnected
    }

    var statusText: String {
        switch connectionState {
        case .idle:
            return "Ready to connect"
        case .scanning:
            return "Scanning for ARCVisor"
        case .discovering:
            return "ARCVisor discovered"
        case .connecting:
            return "Connecting to ARCVisor"
        case .connected:
            return "ARCVisor connected"
        case .failed:
            return "Connection failed"
        case .bluetoothUnavailable:
            return "Bluetooth unavailable"
        }
    }

    mutating func connect() {
        connectionState = .connected
        latestPayload = "ARCVisor paired. Section sync and task overlays are ready."
    }
}

struct RegisteredProfile: Identifiable, Codable {
    let id: UUID
    var accountID: String
    var name: String
    var phoneNumber: String
    var email: String
    var role: AppRole
    var password: String
    var language: AppLanguage

    init(
        id: UUID = UUID(),
        accountID: String,
        name: String,
        phoneNumber: String,
        email: String,
        role: AppRole,
        password: String,
        language: AppLanguage = .english
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.phoneNumber = phoneNumber
        self.email = email
        self.role = role
        self.password = password
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID
        case name
        case phoneNumber
        case email
        case role
        case password
        case language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        accountID = try container.decode(String.self, forKey: .accountID)
        name = try container.decode(String.self, forKey: .name)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        role = try container.decodeIfPresent(AppRole.self, forKey: .role) ?? .worker
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
    }
}
