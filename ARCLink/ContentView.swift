//
//  ContentView.swift
//  test
//
//  Created by Emilia Vu on 3/9/26.
//

import SwiftUI

private let demoAppStorageSuiteName = "ARCLinkDemoDefaults"
private let demoAppStorage = UserDefaults(suiteName: demoAppStorageSuiteName) ?? .standard

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
            demoAppStorage.set(managerPersonalTodosRaw, forKey: "managerPersonalTodosJSON")
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

    private var language: AppLanguage {
        AppLanguage(rawValue: profileLanguageRawValue) ?? .english
    }

    var body: some View {
        Group {
            switch activeRole {
            case .manager:
                ManagerHomeView(profileName: defaultManagerDemoProfile().name, onSignOut: onExitDemo)
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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                demoControlBar
                Color.clear.frame(height: 18)
            }
        }
        .onAppear {
            managerSectionsRaw = encodeSections(mergedSectionsWithDemoSection(from: managerSectionsRaw))
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
        VStack(spacing: 10) {
            HStack {
                Text(localized("Demo Mode", language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

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
                Text(localized("Crew", language)).tag(AppRole.worker)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 72)
        .padding(.top, 8)
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
