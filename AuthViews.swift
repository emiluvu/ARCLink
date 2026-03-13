//
//  AuthViews.swift
//  test
//

import SwiftUI

struct LaunchSplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                AppBrandImage(helmetSize: 40, craneSize: 30, spacing: 4)

                Text("ARCLink")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct SignInOnboardingView: View {
    let onCreateProfile: (String, String, String, String, AppRole, String, String, AppLanguage) -> Void
    let onSignInExisting: () -> Void
    let onEnterDemo: (AppRole, AppLanguage) -> Void

    @AppStorage("hasSelectedAuthLanguage") private var hasSelectedAuthLanguage = false
    @AppStorage("managerSectionsJSON") private var managerSectionsRaw = ""
    @AppStorage("registeredProfilesJSON") private var registeredProfilesRaw = ""
    @AppStorage("profileAccountID") private var profileAccountID = ""
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profilePhoneNumber") private var savedPhoneNumber = ""
    @AppStorage("profileEmail") private var profileEmail = ""
    @AppStorage("profilePassword") private var savedPassword = ""
    @AppStorage("profileRole") private var profileRoleRawValue = ""
    @AppStorage("profileSectionName") private var profileSectionName = ""
    @AppStorage("profileSectionCode") private var profileSectionCode = ""
    @AppStorage("profileLanguage") private var profileLanguageRawValue = AppLanguage.english.rawValue

    @State private var authTab: AuthTab = .createProfile

    @State private var createFirstName = ""
    @State private var createLastName = ""
    @State private var createPhoneNumber = ""
    @State private var createEmail = ""
    @State private var createPassword = ""
    @State private var createSiteCode = ""
    @State private var createSelectedRole: AppRole = .worker
    @State private var authSelectedLanguage: AppLanguage = .english

    @State private var signInPhoneNumber = ""
    @State private var signInPassword = ""

    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var hasConfirmedAuthLanguage = false

    private var createDigitsOnlyPhone: String {
        createPhoneNumber.filter(\.isNumber)
    }

    private var normalizedSiteCode: String {
        normalizeCodeWord(createSiteCode)
    }

    private var availableSections: [ManagerSection] {
        mergedSectionsWithDemoSection(from: managerSectionsRaw)
    }

    private var matchedSection: ManagerSection? {
        availableSections.first(where: { $0.codeWord == normalizedSiteCode })
    }

    private var canCreateProfile: Bool {
        let hasName = !createFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !createLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhone = createDigitsOnlyPhone.count >= 10
        let hasPassword = createPassword.count >= 6
        if createSelectedRole == .manager {
            return hasName && hasPhone && hasPassword
        }
        return hasName && hasPhone && hasPassword && matchedSection != nil
    }

    private var signInDigitsOnlyPhone: String {
        signInPhoneNumber.filter(\.isNumber)
    }

    private var registeredProfiles: [RegisteredProfile] {
        mergedRegisteredProfilesWithDemoAccounts(from: registeredProfilesRaw)
    }

    private var authLanguage: AppLanguage {
        authSelectedLanguage
    }

    @ViewBuilder
    private var authContent: some View {
        if hasConfirmedAuthLanguage {
            authFormView
        } else {
            languageGateView
        }
    }

    var body: some View {
        NavigationView {
            authContent
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .alert("Enter a valid profile", isPresented: $showValidationError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(validationMessage)
                }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            managerSectionsRaw = encodeSections(availableSections)
            seedDefaultDemoProfilesIfNeeded()
            authSelectedLanguage = AppLanguage(rawValue: profileLanguageRawValue) ?? .english
            hasConfirmedAuthLanguage = hasSelectedAuthLanguage
        }
    }

    private var authFormView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text(localized("Welcome to", authLanguage))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 10) {
                        Text("ARCLink")
                            .font(.largeTitle.weight(.bold))

                        Spacer()

                        AppBrandImage(helmetSize: 34, craneSize: 24, spacing: 4)
                        .padding(.trailing, 6)
                        .offset(y: -6)
                    }

                    Button {
                        onEnterDemo(.manager, authSelectedLanguage)
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localized("Open Demo", authLanguage))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(localized("Try the seeded manager and crew experience without signing in.", authLanguage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(uiColor: .secondarySystemGroupedBackground),
                                    Color(uiColor: .tertiarySystemGroupedBackground)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(localized("Mode", authLanguage), selection: $authTab) {
                    ForEach(AuthTab.allCases) { tab in
                        Text(localized(tab.title, authLanguage)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }

            if authTab == .createProfile {
                createProfileSections
            } else {
                signInSections
            }

            Section {
                Picker("Language/Idioma", selection: $authSelectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var languageGateView: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 18) {
                Text("Language/Idioma")
                    .font(.title2.weight(.semibold))

                if authSelectedLanguage == .spanish {
                    Text("Elige tu idioma antes de continuar.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose your language before continuing.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Picker("Language/Idioma", selection: $authSelectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Button(authSelectedLanguage == .spanish ? "Continuar" : "Continue") {
                    hasSelectedAuthLanguage = true
                    hasConfirmedAuthLanguage = true
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var createProfileSections: some View {
        Section(localized("Create Profile", authLanguage)) {
            TextField(localized("First name", authLanguage), text: $createFirstName)
                .keyboardType(.default)
                .textInputAutocapitalization(.words)
            TextField(localized("Last name", authLanguage), text: $createLastName)
                .keyboardType(.default)
                .textInputAutocapitalization(.words)
            TextField(localized("Phone number", authLanguage), text: $createPhoneNumber)
                .keyboardType(.numberPad)
            SecureField(localized("Create password", authLanguage), text: $createPassword)
            TextField(localized("Email (optional)", authLanguage), text: $createEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }

        Section(localized("I am a", authLanguage)) {
            Picker(localized("Role", authLanguage), selection: $createSelectedRole) {
                ForEach(AppRole.allCases) { role in
                    Text(localized(role.title, authLanguage)).tag(role)
                }
            }
            .pickerStyle(.segmented)
        }

        if createSelectedRole == .worker {
            Section(localized("Section Access", authLanguage)) {
                TextField(localized("Section code word", authLanguage), text: $createSiteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Text(localized("Enter the section code word from your manager to join the right crew.", authLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if availableSections.isEmpty {
                    Text(localized("No sections exist yet. Ask your manager to create one and share its code word.", authLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            Button(localized("Create Profile", authLanguage)) {
                createProfileAction()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(createSelectedRole == .worker && availableSections.isEmpty)
        }
    }

    private var signInSections: some View {
        Group {
            Section(localized("Sign In", authLanguage)) {
                TextField(localized("Phone number", authLanguage), text: $signInPhoneNumber)
                    .keyboardType(.numberPad)
                SecureField(localized("Password", authLanguage), text: $signInPassword)
            }

            Section {
                Button(localized("Sign In", authLanguage)) {
                    signInAction()
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func registerWorkerInSection(sectionID: UUID, workerName: String, workerPhone: String) {
        var sections = availableSections
        guard let index = sections.firstIndex(where: { $0.id == sectionID }) else { return }

        if let memberIndex = sections[index].members.firstIndex(where: { $0.phoneNumber == workerPhone }) {
            sections[index].members[memberIndex].name = workerName
        } else {
            sections[index].members.append(SectionMember(name: workerName, phoneNumber: workerPhone))
        }

        managerSectionsRaw = encodeSections(sections)
    }

    private func createProfileAction() {
        guard canCreateProfile else {
            if createFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                createLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                createDigitsOnlyPhone.count < 10 {
                validationMessage = "Add your first name, last name, and a phone number with at least 10 digits."
            } else if createPassword.count < 6 {
                validationMessage = "Create a password with at least 6 characters."
            } else if createSelectedRole == .worker && availableSections.isEmpty {
                validationMessage = "No sections are available yet. A manager needs to create one first."
            } else {
                validationMessage = "Enter a valid section code word generated by your manager."
            }
            showValidationError = true
            return
        }

        let cleanedName = combinedFullName(firstName: createFirstName, lastName: createLastName)
        let cleanedEmail = createEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        if createSelectedRole == .worker, let section = matchedSection {
            registerWorkerInSection(
                sectionID: section.id,
                workerName: cleanedName,
                workerPhone: createDigitsOnlyPhone
            )
            onCreateProfile(
                cleanedName,
                createDigitsOnlyPhone,
                cleanedEmail,
                createPassword,
                createSelectedRole,
                section.name,
                section.codeWord,
                authSelectedLanguage
            )
        } else {
            onCreateProfile(
                cleanedName,
                createDigitsOnlyPhone,
                cleanedEmail,
                createPassword,
                createSelectedRole,
                "",
                "",
                authSelectedLanguage
            )
        }
    }

    private func signInAction() {
        let profiles = persistMergedRegisteredProfiles()

        guard let profile = signInProfile(from: profiles) else {
            if registeredProfiles.isEmpty {
                validationMessage = "No existing profile found. Create a profile first."
            } else {
                validationMessage = "Phone number or password is incorrect."
            }
            showValidationError = true
            return
        }
        profileAccountID = profile.accountID
        profileName = profile.name
        savedPhoneNumber = profile.phoneNumber
        profileEmail = profile.email
        savedPassword = profile.password
        profileRoleRawValue = profile.role.rawValue
        profileLanguageRawValue = profile.language.rawValue
        if profile.role == .worker {
            let workerSection = availableSections.first {
                $0.members.contains(where: { member in
                    member.accountID == profile.accountID || member.phoneNumber == profile.phoneNumber
                })
            }
            profileSectionName = workerSection?.name ?? ""
            profileSectionCode = workerSection?.codeWord ?? ""
        } else {
            profileSectionName = ""
            profileSectionCode = ""
        }
        onSignInExisting()
    }

    private func seedDefaultDemoProfilesIfNeeded() {
        let hasExistingPrimaryProfile = !savedPhoneNumber.isEmpty || !savedPassword.isEmpty || !profileRoleRawValue.isEmpty
        let demoWorkerProfile = defaultWorkerDemoProfile()
        let demoSectionName = "Tower A - Concrete"
        let demoSectionCode = "STEEL-GATE-482"
        registeredProfilesRaw = encodeRegisteredProfiles(registeredProfiles)

        if !hasExistingPrimaryProfile {
            profileAccountID = demoWorkerProfile.accountID
            profileName = demoWorkerProfile.name
            savedPhoneNumber = demoWorkerProfile.phoneNumber
            profileEmail = demoWorkerProfile.email
            savedPassword = demoWorkerProfile.password
            profileRoleRawValue = AppRole.worker.rawValue
            profileSectionName = demoSectionName
            profileSectionCode = demoSectionCode
            profileLanguageRawValue = demoWorkerProfile.language.rawValue
        }
    }

    private func persistMergedRegisteredProfiles() -> [RegisteredProfile] {
        let profiles = registeredProfiles
        registeredProfilesRaw = encodeRegisteredProfiles(profiles)
        return profiles
    }

    private func signInProfile(from profiles: [RegisteredProfile]) -> RegisteredProfile? {
        profiles.first(where: {
            $0.phoneNumber == signInDigitsOnlyPhone &&
            $0.password == signInPassword
        })
    }
}
