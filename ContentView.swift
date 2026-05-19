//
//  ContentView.swift
//  test
//
//  Created by Emilia Vu on 3/9/26.
//

import SwiftUI

private let demoAppStorageSuiteName = "ARCLinkDemoDefaults"
private let demoAppStorage = UserDefaults(suiteName: demoAppStorageSuiteName) ?? .standard
private let sectionLeaderWalkthroughStatusKey = "sectionLeaderDemoWalkthroughStatus"

struct ContentView: View {
    @Environment(BluetoothManager.self) private var bluetoothManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("isInDemoMode") private var isInDemoMode = false
    @AppStorage("demoActiveRole") private var demoActiveRoleRawValue = AppRole.manager.rawValue
    @AppStorage("profileAccountID") private var profileAccountID = ""
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profilePhoneNumber") private var profilePhoneNumber = ""
    @AppStorage("profileEmail") private var profileEmail = ""
    @AppStorage("profilePassword") private var profilePassword = ""
    @AppStorage("profileRole") private var profileRoleRawValue = ""
    @AppStorage("profileSectionName") private var profileSectionName = ""
    @AppStorage("profileSectionCode") private var profileSectionCode = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue
    @AppStorage("registeredProfilesJSON") private var registeredProfilesRaw = ""
    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("managerAssignedSectionCodesJSON") private var managerAssignedSectionCodesRaw = ""
    @AppStorage("managerPersonalTodosJSON") private var managerPersonalTodosRaw = ""
    @AppStorage("managerCrewNicknamesJSON") private var managerCrewNicknamesRaw = ""
    @AppStorage("workerPrivateTaskNotesJSON") private var workerPrivateTaskNotesRaw = ""
    @State private var showsLaunchSplash = true
    @State private var automaticBluetoothSendTask: Task<Void, Never>?
    @State private var lastAutomaticallySentPayload: String?

    private var currentRole: AppRole? {
        AppRole(rawValue: profileRoleRawValue)
    }

    private var demoActiveRole: AppRole {
        AppRole(rawValue: demoActiveRoleRawValue) ?? .manager
    }

    var body: some View {
        Group {
            if showsLaunchSplash {
                LaunchSplashView()
            } else if isInDemoMode {
                DemoModeContainerView(
                    activeRole: demoActiveRole,
                    onSelectRole: { role in
                        activateDemoMode(as: role)
                    },
                    onExitDemo: exitDemoMode
                )
            } else if hasCompletedOnboarding, let role = currentRole {
                switch role {
                case .manager:
                    ManagerHomeView(profileName: profileName, onSignOut: signOut)
                case .worker:
                    WorkerHomeView(
                        profileName: profileName,
                        profilePhoneNumber: profilePhoneNumber,
                        sectionName: profileSectionName,
                        sectionCode: profileSectionCode,
                        onSignOut: signOut
                    )
                }
            } else {
                SignInOnboardingView(
                    onCreateProfile: createProfileAndSignIn,
                    onSignInExisting: signInExistingProfile,
                    onEnterDemo: { role, language in
                        activateDemoMode(as: role, language: language)
                    }
                )
            }
        }
        .onAppear {
            guard showsLaunchSplash else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showsLaunchSplash = false
                }
            }
        }
        .onChange(of: bluetoothManager.isConnected()) {
            if bluetoothManager.isConnected() {
                scheduleAutomaticARCVisorUpdate(forceResend: true)
            } else {
                automaticBluetoothSendTask?.cancel()
                lastAutomaticallySentPayload = nil
            }
        }
        .onChange(of: managerSectionsRaw) {
            scheduleAutomaticARCVisorUpdate()
        }
        .onChange(of: managerPersonalTodosRaw) {
            scheduleAutomaticARCVisorUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: demoAppStorage)) { _ in
            guard isInDemoMode else { return }
            scheduleAutomaticARCVisorUpdate()
        }
        .tint(.arcAccentOrange)
    }

    private func createProfileAndSignIn(
        name: String,
        phoneNumber: String,
        email: String,
        password: String,
        role: AppRole,
        sectionName: String,
        sectionCode: String,
        language: AppLanguage
    ) {
        let accountID = resolvedAccountID(for: phoneNumber)
        profileName = name
        profileAccountID = accountID
        profilePhoneNumber = phoneNumber
        profileEmail = email
        profilePassword = password
        profileRoleRawValue = role.rawValue
        profileSectionName = sectionName
        profileSectionCode = sectionCode
        profileLanguageRawValue = language.rawValue
        upsertRegisteredProfile(
            RegisteredProfile(
                accountID: accountID,
                name: name,
                phoneNumber: phoneNumber,
                email: email,
                role: role,
                password: password,
                language: language
            )
        )
        hasCompletedOnboarding = true
    }

    private func signInExistingProfile() {
        if profileAccountID.isEmpty {
            let accountID = resolvedAccountID(for: profilePhoneNumber)
            profileAccountID = accountID
            upsertRegisteredProfile(
                RegisteredProfile(
                    accountID: accountID,
                    name: profileName,
                    phoneNumber: profilePhoneNumber,
                    email: profileEmail,
                    role: AppRole(rawValue: profileRoleRawValue) ?? .worker,
                    password: profilePassword,
                    language: AppLanguage(rawValue: profileLanguageRawValue) ?? .english
                )
            )
        }
        hasCompletedOnboarding = true
    }

    private func signOut() {
        hasCompletedOnboarding = false
    }

    private func activateDemoMode(as role: AppRole, language: AppLanguage? = nil) {
        let selectedLanguage = language ?? (AppLanguage(rawValue: profileLanguageRawValue) ?? .english)
        configureDemoSession(for: role, language: selectedLanguage, resetData: !isInDemoMode)
        demoActiveRoleRawValue = role.rawValue
        hasCompletedOnboarding = false
        isInDemoMode = true
    }

    private func exitDemoMode() {
        isInDemoMode = false
        demoAppStorage.removePersistentDomain(forName: demoAppStorageSuiteName)
    }

    private func demoProfile(for role: AppRole) -> RegisteredProfile {
        switch role {
        case .manager:
            return defaultManagerDemoProfile()
        case .worker:
            return defaultWorkerDemoProfile()
        }
    }

    private func configureDemoSession(for role: AppRole, language: AppLanguage, resetData: Bool) {
        if resetData {
            demoAppStorage.removePersistentDomain(forName: demoAppStorageSuiteName)
            demoAppStorage.set(
                encodeRegisteredProfiles(mergedRegisteredProfilesWithDemoAccounts(from: registeredProfilesRaw)),
                forKey: "registeredProfilesJSON"
            )
            demoAppStorage.set(
                encodeSections(mergedSectionsWithDemoSection(from: managerSectionsRaw)),
                forKey: "managerSectionsJSON"
            )
            demoAppStorage.set(managerAssignedSectionCodesRaw, forKey: "managerAssignedSectionCodesJSON")
            demoAppStorage.set(encodeMemberTodos(defaultManagerDemoPersonalTodos()), forKey: "managerPersonalTodosJSON")
            demoAppStorage.set(managerCrewNicknamesRaw, forKey: "managerCrewNicknamesJSON")
            demoAppStorage.set(workerPrivateTaskNotesRaw, forKey: "workerPrivateTaskNotesJSON")
        }

        let profile = demoProfile(for: role)
        demoAppStorage.set(profile.accountID, forKey: "profileAccountID")
        demoAppStorage.set(profile.name, forKey: "profileName")
        demoAppStorage.set(profile.phoneNumber, forKey: "profilePhoneNumber")
        demoAppStorage.set(profile.email, forKey: "profileEmail")
        demoAppStorage.set(profile.password, forKey: "profilePassword")
        demoAppStorage.set(profile.role.rawValue, forKey: "profileRole")
        demoAppStorage.set(language.rawValue, forKey: "profileLanguage")
        if profile.role == .manager {
            let assignedCodes = managerAssignedSectionCodesRaw.isEmpty
                ? encodeStringArray(defaultLeadershipAssignedSectionCodes(for: profile.accountID))
                : managerAssignedSectionCodesRaw
            demoAppStorage.set(assignedCodes, forKey: "managerAssignedSectionCodesJSON")
        }

        let sections = decodeSections(from: demoAppStorage.string(forKey: "managerSectionsJSON") ?? "")
        if profile.role == .worker,
           let workerSection = sections.first(where: { section in
               section.members.contains(where: { member in
                   member.accountID == profile.accountID || member.phoneNumber == profile.phoneNumber
               })
           }) {
            demoAppStorage.set(workerSection.name, forKey: "profileSectionName")
            demoAppStorage.set(workerSection.codeWord, forKey: "profileSectionCode")
        } else {
            demoAppStorage.set("", forKey: "profileSectionName")
            demoAppStorage.set("", forKey: "profileSectionCode")
        }
    }

    private func resolvedAccountID(for phoneNumber: String) -> String {
        let profiles = decodeRegisteredProfiles(from: registeredProfilesRaw)
        if let existing = profiles.first(where: { $0.phoneNumber == phoneNumber }) {
            return existing.accountID
        }
        return generateUniqueAccountID(existingIDs: Set(profiles.map(\.accountID)))
    }

    private func upsertRegisteredProfile(_ profile: RegisteredProfile) {
        var profiles = decodeRegisteredProfiles(from: registeredProfilesRaw)
        if let index = profiles.firstIndex(where: { $0.accountID == profile.accountID || $0.phoneNumber == profile.phoneNumber }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        registeredProfilesRaw = encodeRegisteredProfiles(profiles)
    }

    private func scheduleAutomaticARCVisorUpdate(forceResend: Bool = false) {
        guard bluetoothManager.isConnected() else { return }
        automaticBluetoothSendTask?.cancel()
        automaticBluetoothSendTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            sendAutomaticARCVisorUpdateIfPossible(forceResend: forceResend)
        }
    }

    private func sendAutomaticARCVisorUpdateIfPossible(forceResend: Bool = false) {
        guard bluetoothManager.isConnected() else { return }
        guard let payloadContext else { return }
        guard let payload = try? encodedARCVisorPayload(from: payloadContext) else { return }
        guard forceResend || payload != lastAutomaticallySentPayload else { return }
        do {
            try bluetoothManager.writeString(payload)
            lastAutomaticallySentPayload = payload
        } catch {
            return
        }
    }

    private var payloadContext: ARCVisorPayloadContext? {
        let resolvedRole: AppRole?
        let resolvedName: String
        let resolvedAccountID: String
        let resolvedPhoneNumber: String
        let resolvedSectionsRaw: String
        let resolvedAssignedCodesRaw: String
        let resolvedPersonalTodosRaw: String

        if isInDemoMode {
            resolvedRole = demoActiveRole
            resolvedName = demoAppStorage.string(forKey: "profileName") ?? demoProfile(for: demoActiveRole).name
            resolvedAccountID = demoAppStorage.string(forKey: "profileAccountID") ?? demoProfile(for: demoActiveRole).accountID
            resolvedPhoneNumber = demoAppStorage.string(forKey: "profilePhoneNumber") ?? demoProfile(for: demoActiveRole).phoneNumber
            resolvedSectionsRaw = demoAppStorage.string(forKey: "managerSectionsJSON") ?? ""
            resolvedAssignedCodesRaw = demoAppStorage.string(forKey: "managerAssignedSectionCodesJSON") ?? ""
            resolvedPersonalTodosRaw = demoAppStorage.string(forKey: "managerPersonalTodosJSON") ?? ""
        } else {
            resolvedRole = currentRole
            resolvedName = profileName
            resolvedAccountID = profileAccountID
            resolvedPhoneNumber = profilePhoneNumber
            resolvedSectionsRaw = managerSectionsRaw
            resolvedAssignedCodesRaw = managerAssignedSectionCodesRaw
            resolvedPersonalTodosRaw = managerPersonalTodosRaw
        }

        guard let resolvedRole else { return nil }

        return ARCVisorPayloadContext(
            userName: abbreviatedDisplayName(resolvedName),
            roleTitle: resolvedRole.title,
            profileAccountID: resolvedAccountID,
            profilePhoneNumber: resolvedPhoneNumber,
            managerSectionsRaw: resolvedSectionsRaw,
            assignedSectionCodesRaw: resolvedAssignedCodesRaw,
            managerPersonalTodosRaw: resolvedPersonalTodosRaw
        )
    }
}

private struct DemoModeContainerView: View {
    let activeRole: AppRole
    let onSelectRole: (AppRole) -> Void
    let onExitDemo: () -> Void

    @AppStorage("managerSectionsJSON", store: demoAppStorage) private var managerSectionsRaw = ""
    @AppStorage("profileLanguage", store: demoAppStorage) private var profileLanguageRawValue = AppLanguage.english.rawValue
    @State private var showManagerWalkthrough = false
    @State private var walkthroughStepIndex = 0
    @State private var walkthroughFocusStepIndex = 0
    @State private var hasHandledInitialWalkthrough = false
    @State private var isManagerWalkthroughSettling = false
    @State private var managerWalkthroughDestination: DemoDestination = .home
    @State private var isDemoControlExpanded = false
    @State private var showFieldwireDemo = false

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    private var primaryManagedSectionID: UUID? {
        mergedSectionsWithDemoSection(from: managerSectionsRaw)
            .first(where: { $0.ownerAccountID == defaultManagerDemoProfile().accountID && $0.parentSectionID == nil })?
            .id
    }

    private var managerWalkthroughSteps: [WalkthroughStep] {
        let primarySectionDetail = primaryManagedSectionID.map { DemoDestination.sectionDetail(sectionID: $0) } ?? .home
        let primarySectionTasks = primaryManagedSectionID.map { DemoDestination.sectionTasks(sectionID: $0) } ?? .home
        let primarySectionChats = primaryManagedSectionID.map { DemoDestination.sectionChats(sectionID: $0) } ?? .home
        let primarySectionTimeClock = primaryManagedSectionID.map { DemoDestination.sectionTimeClock(sectionID: $0) } ?? .home

        return [
            WalkthroughStep(
                id: 0,
                destination: .home,
                targetID: .arcVisorButton,
                title: localized("Open ARCVisor", language),
                message: localized("Use the ARCVisor row on the main dashboard to open the connected visor workspace and monitor live visor activity.", language)
            ),
            WalkthroughStep(
                id: 1,
                destination: .home,
                targetID: .airQualityButton,
                title: localized("Air Quality Data", language),
                message: localized("The Air Quality Data row opens live environmental readings and safety alerts directly from the Crew Lead dashboard.", language)
            ),
            WalkthroughStep(
                id: 2,
                destination: .home,
                targetID: .managerEmergency,
                title: localized("Emergency Alert Controls", language),
                message: localized("The Emergency section is now pinned near the top so Crew Leads can quickly send an evacuation alert without mixing it with routine controls.", language)
            ),
            WalkthroughStep(
                id: 3,
                destination: .home,
                targetID: .crewSnapshot,
                title: localized("Crew Snapshot", language),
                message: localized("Crew Snapshot now rolls up all managed members across sections with on-site counts, verification load, status, and completion progress in one place.", language)
            ),
            WalkthroughStep(
                id: 4,
                destination: .home,
                targetID: .overallTodos,
                title: localized("Overall To-Do List", language),
                message: localized("This dashboard list helps Crew Leads review leadership tasks, verification items, and priority work without leaving the home screen.", language)
            ),
            WalkthroughStep(
                id: 5,
                destination: .home,
                targetID: .managedSectionCard,
                title: localized("Crew Management", language),
                message: localized("Managed Crews is the main Crew Lead control area for opening crews, reviewing status, and organizing work by crew or site.", language)
            ),
            WalkthroughStep(
                id: 6,
                destination: .home,
                targetID: .profile,
                title: localized("Profile and Settings", language),
                message: localized("The profile row gives Crew Leads access to account details, password changes, language settings, and shortcuts-related options.", language)
            ),
            WalkthroughStep(
                id: 7,
                destination: primarySectionDetail,
                targetID: .sectionSnapshot,
                title: localized("Crew Snapshot", language),
                message: localized("Inside each crew, the snapshot shows member count, on-site status, due-today work, verification load, and progress bars for each person.", language)
            ),
            WalkthroughStep(
                id: 8,
                destination: primarySectionDetail,
                targetID: .sectionBreakTime,
                title: localized("Break Time Alert", language),
                message: localized("Use the Break Time control from the section snapshot when you need to alert one section without sending a full emergency evacuation.", language)
            ),
            WalkthroughStep(
                id: 9,
                destination: primarySectionDetail,
                targetID: .sectionFeatureControls,
                title: localized("Crew Feature Controls", language),
                message: localized("The crew controls let Crew Leads manage which tools are active, including time clock, group chats, crew tasks, and personal to-dos.", language)
            ),
            WalkthroughStep(
                id: 10,
                destination: primarySectionDetail,
                targetID: .sectionMembers,
                title: localized("Member Management", language),
                message: localized("Inside the section, Crew Leads can open the member area to review assigned people, roles, and field status.", language)
            ),
            WalkthroughStep(
                id: 11,
                destination: primarySectionDetail,
                targetID: .sectionSubsections,
                title: localized("Sub-crew Management", language),
                message: localized("Open the sub-crew area inside the crew to organize smaller crews, zones, or phases under the main crew.", language)
            ),
            WalkthroughStep(
                id: 12,
                destination: primarySectionChats,
                targetID: .sectionChats,
                title: localized("Group Chats and Pinned Messages", language),
                message: localized("Crew chats keep crews aligned with pinned updates, media sharing, reactions, and message visibility controls.", language)
            ),
            WalkthroughStep(
                id: 13,
                destination: primarySectionDetail,
                targetID: .sectionVerification,
                title: localized("Task Review and Verification", language),
                message: localized("The section task area shows completion progress and verification status so leads can follow work from assigned to confirmed.", language)
            ),
            WalkthroughStep(
                id: 14,
                destination: primarySectionTasks,
                targetID: .sectionTaskAddButton,
                title: localized("Crew Task Creation", language),
                message: localized("Crew Leads create section tasks here with assignees, due dates, priorities, checklists, and attachments.", language)
            ),
            WalkthroughStep(
                id: 15,
                destination: primarySectionTasks,
                targetID: .sectionTasks,
                title: localized("Progress Oversight", language),
                message: localized("Task summaries inside the section make it easy to track progress, spot stalled work, and review what still needs attention.", language)
            ),
            WalkthroughStep(
                id: 16,
                destination: primarySectionTimeClock,
                targetID: .memberTimeClock,
                title: localized("Time Clock Visibility", language),
                message: localized("Member detail time clock data gives Crew Leads visibility into attendance, time entries, and on-site status.", language)
            )
        ]
    }

    var body: some View {
        Group {
            switch activeRole {
            case .manager:
                ManagerHomeView(
                    profileName: defaultManagerDemoProfile().name,
                    walkthroughDestination: showManagerWalkthrough ? managerWalkthroughDestination : .home,
                    walkthroughFocusTarget: showManagerWalkthrough ? managerWalkthroughSteps[walkthroughFocusStepIndex].targetID : nil,
                    onSignOut: onExitDemo
                )
            case .worker:
                WorkerHomeView(
                    profileName: defaultWorkerDemoProfile().name,
                    profilePhoneNumber: defaultWorkerDemoProfile().phoneNumber,
                    sectionName: demoWorkerSection?.name ?? "",
                    sectionCode: demoWorkerSection?.codeWord ?? "",
                    onSignOut: onExitDemo
                )
            }
        }
        .defaultAppStorage(demoAppStorage)
        .overlayPreferenceValue(WalkthroughTargetPreferenceKey.self) { preferences in
            GeometryReader { geometryProxy in
                if activeRole == .manager, showManagerWalkthrough, !isManagerWalkthroughSettling {
                    CoachMarkOverlay(
                        steps: managerWalkthroughSteps,
                        currentStepIndex: $walkthroughStepIndex,
                        targetFrame: currentManagerWalkthroughTargetFrame(
                            preferences: preferences,
                            geometryProxy: geometryProxy
                        ),
                        onBack: {
                            transitionManagerWalkthrough(to: max(0, walkthroughStepIndex - 1))
                        },
                        onSkip: {
                            finishManagerWalkthrough(status: "skipped")
                        },
                        onNext: {
                            transitionManagerWalkthrough(to: walkthroughStepIndex + 1)
                        },
                        onComplete: {
                            finishManagerWalkthrough(status: "completed")
                        }
                    )
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            demoControlBar
                .padding(.trailing, 12)
                .padding(.bottom, 12)
        }
        .sheet(isPresented: $showFieldwireDemo) {
            NavigationView {
                FieldwireDemoSandboxView()
            }
            .navigationViewStyle(.stack)
        }
        .onAppear {
            managerSectionsRaw = encodeSections(mergedSectionsWithDemoSection(from: managerSectionsRaw))
            guard !hasHandledInitialWalkthrough else { return }
            hasHandledInitialWalkthrough = true
            if activeRole == .manager {
                startManagerWalkthrough()
            }
        }
    }

    private var demoWorkerSection: ManagerSection? {
        mergedSectionsWithDemoSection(from: managerSectionsRaw).first(where: { section in
            section.members.contains(where: { member in
                member.accountID == defaultWorkerDemoProfile().accountID ||
                member.phoneNumber == defaultWorkerDemoProfile().phoneNumber
            })
        })
    }

    private var demoControlBar: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDemoControlExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isDemoControlExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                    Text("Demo")
                        .font(.caption.weight(.semibold))
                    if isDemoControlExpanded {
                        Text(activeRole == .manager ? localized("Crew Lead", language) : localized("Crew Member", language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, isDemoControlExpanded ? 10 : 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
#if os(iOS)
            .onHover { isHovering in
                guard isHovering, !isDemoControlExpanded else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDemoControlExpanded = true
                }
            }
#endif

            if isDemoControlExpanded {
                HStack {
                    Spacer()
                    Button(localized("Exit Demo", language)) {
                        onExitDemo()
                    }
                    .font(.caption.weight(.semibold))
                }

                Picker(
                    localized("View As", language),
                    selection: Binding(
                        get: { activeRole },
                        set: { onSelectRole($0) }
                    )
                ) {
                    Text(localized("Crew Lead", language)).tag(AppRole.manager)
                    Text(localized("Crew Member", language)).tag(AppRole.worker)
                }
                .pickerStyle(.segmented)
                .transition(.move(edge: .top).combined(with: .opacity))

                Button("Fieldwire Demo") {
                    showFieldwireDemo = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .transition(.move(edge: .top).combined(with: .opacity))

                if activeRole == .manager {
                    Button(localized("Replay Walkthrough", language)) {
                        startManagerWalkthrough()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.arcAccentOrange)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isDemoControlExpanded ? 10 : 6)
        .frame(width: isDemoControlExpanded ? 210 : nil, alignment: .trailing)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }

    private func startManagerWalkthrough() {
        showManagerWalkthrough = true
        UserDefaults.standard.removeObject(forKey: sectionLeaderWalkthroughStatusKey)
        transitionManagerWalkthrough(to: 0)
    }

    private func finishManagerWalkthrough(status: String) {
        UserDefaults.standard.set(status, forKey: sectionLeaderWalkthroughStatusKey)
        isManagerWalkthroughSettling = false
        showManagerWalkthrough = false
    }

    private func transitionManagerWalkthrough(to index: Int) {
        guard managerWalkthroughSteps.indices.contains(index) else { return }
        let step = managerWalkthroughSteps[index]
        isManagerWalkthroughSettling = true
        managerWalkthroughDestination = step.destination
        walkthroughFocusStepIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            walkthroughStepIndex = index
            isManagerWalkthroughSettling = false
        }
    }

    private func currentManagerWalkthroughTargetFrame(
        preferences: [WalkthroughTargetID: Anchor<CGRect>],
        geometryProxy: GeometryProxy
    ) -> CGRect? {
        guard managerWalkthroughSteps.indices.contains(walkthroughStepIndex),
              let targetID = managerWalkthroughSteps[walkthroughStepIndex].targetID,
              let anchor = preferences[targetID] else {
            return nil
        }
        return geometryProxy[anchor]
    }
}

private struct FieldwireDemoSandboxView: View {
    private enum SandboxPanel: String, CaseIterable, Identifiable {
        case overview
        case importPreview
        case mapping

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview:
                return "Overview"
            case .importPreview:
                return "Import Preview"
            case .mapping:
                return "ARCLink Mapping"
            }
        }
    }

    private struct FieldwireProject: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let region: String
        let crewName: String
        let status: String
        let tasks: [FieldwireTask]
    }

    private struct FieldwireTask: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let assignee: String
        let dueLabel: String
        let location: String
        let priority: String
        let checklistCount: Int
    }

    private struct ARCLinkMappedTask: Identifiable {
        let id = UUID()
        let title: String
        let destinationCrew: String
        let assigneeMatch: String
        let notes: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPanel: SandboxPanel = .overview
    @State private var selectedProjectID: UUID?
    @State private var hasLoadedSampleImport = false
    @State private var lastSandboxSync: Date?

    private let sampleProjects: [FieldwireProject] = [
        FieldwireProject(
            name: "Tower A Podium Concrete",
            region: "US",
            crewName: "Concrete Crew",
            status: "Ready for sandbox import",
            tasks: [
                FieldwireTask(
                    title: "Confirm pump truck access route",
                    assignee: "Maya Chen",
                    dueLabel: "Today 8:30 AM",
                    location: "South gate staging",
                    priority: "Medium",
                    checklistCount: 3
                ),
                FieldwireTask(
                    title: "Finalize slab prep for afternoon pour",
                    assignee: "Luis Martinez",
                    dueLabel: "Tomorrow 3:30 PM",
                    location: "Deck 2 west bay",
                    priority: "High",
                    checklistCount: 5
                ),
                FieldwireTask(
                    title: "Review barricade placement before pour",
                    assignee: "Arjun Patel",
                    dueLabel: "Today 12:00 PM",
                    location: "Podium edge protection",
                    priority: "High",
                    checklistCount: 2
                )
            ]
        ),
        FieldwireProject(
            name: "Steel Erection Phase 3",
            region: "US",
            crewName: "Structural Crew",
            status: "Ready for sandbox import",
            tasks: [
                FieldwireTask(
                    title: "Coordinate crane window and delivery lane",
                    assignee: "Dana Brooks",
                    dueLabel: "Today 10:00 AM",
                    location: "Laydown yard",
                    priority: "High",
                    checklistCount: 4
                ),
                FieldwireTask(
                    title: "Review afternoon hoisting permit updates",
                    assignee: "Jordan Kim",
                    dueLabel: "Today 4:00 PM",
                    location: "North tower pick zone",
                    priority: "Medium",
                    checklistCount: 1
                )
            ]
        )
    ]

    private var selectedProject: FieldwireProject? {
        if let selectedProjectID {
            return sampleProjects.first(where: { $0.id == selectedProjectID })
        }
        return sampleProjects.first
    }

    private var mappedTasks: [ARCLinkMappedTask] {
        guard let selectedProject else { return [] }
        return selectedProject.tasks.map { task in
            ARCLinkMappedTask(
                title: task.title,
                destinationCrew: selectedProject.crewName,
                assigneeMatch: task.assignee,
                notes: "\(task.location) • \(task.priority) priority • \(task.checklistCount) checklist items"
            )
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fieldwire Demo Sandbox")
                        .font(.title3.weight(.semibold))
                    Text("This page is isolated from the rest of ARCLink. It only previews how a read-only Fieldwire import could flow into ARCLink crews and tasks.")
                        .foregroundStyle(.secondary)
                    Text("No live API calls. No data is written into ARCLink storage.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 4)
            }

            Section("Sandbox View") {
                Picker("Sandbox View", selection: $selectedPanel) {
                    ForEach(SandboxPanel.allCases) { panel in
                        Text(panel.title).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch selectedPanel {
            case .overview:
                overviewSection
            case .importPreview:
                importPreviewSection
            case .mapping:
                mappingSection
            }
        }
        .navigationTitle("Fieldwire Demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            selectedProjectID = selectedProjectID ?? sampleProjects.first?.id
        }
    }

    @ViewBuilder
    private var overviewSection: some View {
        Section("Connection Model") {
            labeledValueRow(title: "Mode", value: "Read-only sandbox")
            labeledValueRow(title: "Auth", value: "Refresh token -> access token")
            labeledValueRow(title: "Region handling", value: "US / EU project routing")
            labeledValueRow(title: "Recommended first step", value: "Project + task import only")
            labeledValueRow(title: "Source of truth", value: "Fieldwire project data, ARCLink crew operations")
        }

        Section("Why Start Here") {
            Text("This isolates the riskiest part of the integration: project and task intake.")
            Text("It avoids two-way sync conflicts while proving the value of bringing Fieldwire tasks into ARCLink crew workflows.")
        }

        Section("Next Build Steps") {
            Text("1. Add Fieldwire connection settings: region, tokens, selected projects.")
            Text("2. Fetch projects and tasks into a sync service outside the SwiftUI views.")
            Text("3. Map imported tasks into ARCLink crew tasks using crew name and assignee matching.")
            Text("4. Keep write-back disabled until source-of-truth rules are settled.")
        }
    }

    @ViewBuilder
    private var importPreviewSection: some View {
        Section("Sandbox Controls") {
            Picker("Sample Project", selection: Binding(
                get: { selectedProject?.id ?? sampleProjects.first?.id ?? UUID() },
                set: { selectedProjectID = $0 }
            )) {
                ForEach(sampleProjects) { project in
                    Text(project.name).tag(project.id)
                }
            }

            Button(hasLoadedSampleImport ? "Run Sample Import Again" : "Run Sample Import") {
                hasLoadedSampleImport = true
                lastSandboxSync = Date()
            }
            .buttonStyle(.borderedProminent)
            .tint(.arcAccentOrange)

            if let lastSandboxSync {
                Text("Last sandbox import: \(lastSandboxSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let selectedProject {
            Section("Imported Project") {
                labeledValueRow(title: "Project", value: selectedProject.name)
                labeledValueRow(title: "Mapped Crew", value: selectedProject.crewName)
                labeledValueRow(title: "Region", value: selectedProject.region)
                labeledValueRow(title: "Status", value: selectedProject.status)
                labeledValueRow(title: "Tasks", value: "\(selectedProject.tasks.count)")
            }

            Section("Fieldwire Tasks") {
                ForEach(selectedProject.tasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(task.title)
                                .font(.headline)
                            Spacer()
                            Text(task.priority)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.arcAccentOrange.opacity(0.12), in: Capsule())
                        }
                        Text("Assignee: \(task.assignee)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Due: \(task.dueLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Location: \(task.location)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var mappingSection: some View {
        if !hasLoadedSampleImport {
            Section {
                Text("Run the sample import first to preview how Fieldwire tasks would map into ARCLink.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("ARCLink Mapping Preview") {
                ForEach(mappedTasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.headline)
                        Text("Destination crew: \(task.destinationCrew)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Assignee match: \(task.assigneeMatch)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Recommended Production Rules") {
                Text("Only import Fieldwire tasks into ARCLink after a project-to-crew mapping is explicitly approved.")
                Text("Match assignees by email, phone number, or stored external user ID before assigning imported work.")
                Text("Keep comments, forms, and photos read-only until conflict rules are defined.")
            }
        }
    }

    private func labeledValueRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ContentViewPreviewContainer: View {
    private let previewDefaults = UserDefaults(suiteName: "ContentViewPreviewDefaults") ?? .standard

    var body: some View {
        ContentView()
            .defaultAppStorage(previewDefaults)
            .onAppear {
                previewDefaults.removePersistentDomain(forName: "ContentViewPreviewDefaults")
            }
    }
}

#Preview {
    ContentViewPreviewContainer()
}
