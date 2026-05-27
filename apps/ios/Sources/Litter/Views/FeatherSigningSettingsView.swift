import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FeatherSigningSettingsView: View {
    @State private var snapshot = FeatherSigningMaterialStore.snapshot(checkRevocation: false)
    @State private var options = FeatherSigningOptions.load()
    @State private var p12URL: URL?
    @State private var profileURL: URL?
    @State private var p12Password = ""
    @State private var certificateNickname = ""
    @State private var importingP12 = false
    @State private var importingProfile = false
    @State private var importingPairing = false
    @State private var importingIPA = false
    @State private var importingEntitlements = false
    @State private var importingDylib = false
    @State private var importingFramework = false
    @State private var importingTweak = false
    @State private var isWorking = false
    @State private var lastOutput: String?
    @State private var alert: SigningAlert?

    var body: some View {
        List {
            upstreamSourceSection
            certificateSection
            pairingSection
            appSection
            modifySection
            featherOptionsSection
            actionSection
            if let lastOutput, !lastOutput.isEmpty {
                outputSection(lastOutput)
            }
        }
        .navigationTitle("Signing")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(LitterTheme.backgroundGradient.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { refresh() }
                    .disabled(isWorking)
            }
        }
        .fileImporter(isPresented: $importingP12, allowedContentTypes: [.litterP12, .litterPFX, .data], allowsMultipleSelection: false) { result in
            selectStagedURL(result, allowedExtensions: ["p12", "pfx"], label: "certificate", assign: { p12URL = $0 })
        }
        .fileImporter(isPresented: $importingProfile, allowedContentTypes: [.litterMobileProvision, .litterProvisionProfile, .data], allowsMultipleSelection: false) { result in
            selectStagedURL(result, allowedExtensions: ["mobileprovision", "provisionprofile"], label: "provisioning profile", assign: { profileURL = $0 })
        }
        .fileImporter(isPresented: $importingPairing, allowedContentTypes: [.litterPairing, .litterMobileDevicePairing, .propertyList, .data], allowsMultipleSelection: false) { result in
            importFile(result) { try await FeatherSigningMaterialStore.importPairingFile(from: $0) }
        }
        .fileImporter(isPresented: $importingIPA, allowedContentTypes: [.litterIPA, .zip, .data], allowsMultipleSelection: false) { result in
            importFile(result) { try await FeatherSigningMaterialStore.importIPA(from: $0) }
        }
        .fileImporter(isPresented: $importingEntitlements, allowedContentTypes: [.litterEntitlements, .propertyList, .xml, .data], allowsMultipleSelection: false) { result in
            importFile(result) { try await FeatherSigningMaterialStore.importEntitlements(from: $0) }
        }
        .fileImporter(isPresented: $importingDylib, allowedContentTypes: [.litterDylib, .data], allowsMultipleSelection: false) { result in
            importFile(result) { try await FeatherSigningMaterialStore.importDylib(from: $0) }
        }
        .fileImporter(isPresented: $importingFramework, allowedContentTypes: [.folder, .litterFramework, .litterPlugin, .litterAppeX], allowsMultipleSelection: false) { result in
            importFile(result) { try await FeatherSigningMaterialStore.importFrameworkOrPlugin(from: $0) }
        }
        .fileImporter(isPresented: $importingTweak, allowedContentTypes: [.litterDeb, .litterDylib, .litterZip, .data], allowsMultipleSelection: false) { result in
            importFile(result) { try await FeatherSigningMaterialStore.importTweak(from: $0) }
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .task { refresh() }
        .onDisappear { options.save() }
        .onChange(of: options) { _, newValue in newValue.save() }
    }

    private var upstreamSourceSection: some View {
        Section {
            sourceRow("SideStore", detail: "ThirdParty/SideStore/Source")
            sourceRow("Feather", detail: "ThirdParty/Feather/Source")
            sourceRow("LocalDevVPN", detail: "ThirdParty/SideStore/LocalDevVPN-Source")
        } header: {
            Text("Upstream Sources")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("This screen follows Feather's certificate, tunnel, and signing option files while keeping SideStore as the store/install/refresh transport.")
        }
    }

    private var certificateSection: some View {
        Section {
            statusRow("Saved Certificate", value: snapshot.certificateState.statusDetail, ready: snapshot.certificateState.isUsable)
            statusRow("Saved Profile", value: snapshot.provisioningProfile?.shortDetail ?? "Missing", ready: snapshot.provisioningProfile != nil)

            Button { importingP12 = true } label: {
                Label(p12URL?.lastPathComponent ?? "Import .p12 / .pfx", systemImage: "key.fill")
            }
            .foregroundStyle(LitterTheme.accent)

            Button { importingProfile = true } label: {
                Label(profileURL?.lastPathComponent ?? "Import .mobileprovision", systemImage: "doc.badge.gearshape")
            }
            .foregroundStyle(LitterTheme.accent)

            SecureField("Certificate password", text: $p12Password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Nickname", text: $certificateNickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                saveCertificate()
            } label: {
                Label("Save Certificate", systemImage: "checkmark.seal.fill")
            }
            .disabled(p12URL == nil || profileURL == nil || isWorking)
            .foregroundStyle(LitterTheme.accent)

            if snapshot.certificate != nil || snapshot.provisioningProfile != nil {
                Button(role: .destructive) {
                    FeatherSigningMaterialStore.clearCertificate()
                    refresh()
                } label: {
                    Label("Clear Certificate", systemImage: "trash")
                }
            }
        } header: {
            Text("Certificates")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("Matches Feather's p12 + mobileprovision import flow and validates password, private key, certificate trust/revocation, profile expiration, and profile/certificate match before saving.")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private var pairingSection: some View {
        Section {
            statusRow("Pairing File", value: snapshot.pairingFile?.shortDetail ?? "Missing", ready: snapshot.pairingFile != nil)
            statusRow("LocalDevVPN", value: snapshot.localDevVPNState.isConnected ? "Ready" : "Not Ready", ready: snapshot.localDevVPNState.isConnected)
            Text(snapshot.localDevVPNState.detail)
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)

            Button { importingPairing = true } label: {
                Label("Import Pairing File", systemImage: "square.and.arrow.down")
            }
            .foregroundStyle(LitterTheme.accent)

            Button { openLocalDevVPN() } label: {
                Label("Open LocalDevVPN", systemImage: "link")
            }
            .foregroundStyle(LitterTheme.accent)
        } header: {
            Text("Pairing + LocalDevVPN")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("Pairing is saved as SideStore's ALTPairingFile.mobiledevicepairing and Feather's pairingFile.plist, then staged into fakefs for bots and BuildKit.")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private var appSection: some View {
        Section {
            statusRow("IPA", value: snapshot.importedIPA?.shortDetail ?? "Missing", ready: snapshot.importedIPA != nil)
            Button { importingIPA = true } label: {
                Label("Import IPA", systemImage: "app.badge")
            }
            .foregroundStyle(LitterTheme.accent)

            TextField("Name", text: $options.appName)
                .textInputAutocapitalization(.words)
            TextField("Bundle Identifier", text: $options.bundleIdentifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Version", text: $options.appVersion)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            statusRow("SideStore Apple ID", value: NyxianAppleIDStore.load()?.statusDetail ?? "Sign in from SideStore Settings", ready: NyxianAppleIDStore.isLoggedIn)

            Picker("Signing Account", selection: $options.signingMode) {
                ForEach(FeatherSigningOptions.SigningMode.allCases) { value in
                    Text(value.label).tag(value)
                }
            }

            Picker("Signing Type", selection: $options.signingType) {
                ForEach(FeatherSigningOptions.SigningType.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
        } header: {
            Text("App")
                .foregroundStyle(LitterTheme.textSecondary)
        } footer: {
            Text("Apple ID sign-in, 2FA, Anisette, and team selection use the embedded SideStore Settings screen. This screen only selects the credential path for signing.")
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private var modifySection: some View {
        Section {
            fileCollectionRow("Existing Dylibs", records: snapshot.dylibs, importAction: { importingDylib = true }, clearAction: {
                FeatherSigningMaterialStore.clearDylibs(); refresh()
            })
            multilineField("Remove Dylibs", text: $options.removeDylibsText, prompt: "@executable_path/Old.dylib")
            fileCollectionRow("Frameworks & PlugIns", records: snapshot.frameworksAndPlugins, importAction: { importingFramework = true }, clearAction: {
                FeatherSigningMaterialStore.clearFrameworksAndPlugins(); refresh()
            })
            fileCollectionRow("Tweaks", records: snapshot.tweaks, importAction: { importingTweak = true }, clearAction: {
                FeatherSigningMaterialStore.clearTweaks(); refresh()
            })
            statusRow("Entitlements", value: snapshot.entitlements?.shortDetail ?? "None", ready: snapshot.entitlements != nil)
            Button { importingEntitlements = true } label: {
                Label("Import Entitlements", systemImage: "doc.text")
            }
            .foregroundStyle(LitterTheme.accent)
            if snapshot.entitlements != nil {
                Button(role: .destructive) {
                    FeatherSigningMaterialStore.clearEntitlements(); refresh()
                } label: {
                    Label("Clear Entitlements", systemImage: "trash")
                }
            }
            multilineField("Remove Files", text: $options.removeFilesText, prompt: "Frameworks/CydiaSubstrate.framework")
            multilineField("Properties", text: $options.customPropertiesText, prompt: "key=value")
        } header: {
            Text("Modify")
                .foregroundStyle(LitterTheme.textSecondary)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private var featherOptionsSection: some View {
        Section {
            Picker("Appearance", selection: $options.appAppearance) {
                ForEach(FeatherSigningOptions.AppAppearance.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            Picker("Minimum Requirement", selection: $options.minimumRequirement) {
                ForEach(FeatherSigningOptions.MinimumRequirement.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            Picker("Injection Path", selection: $options.injectPath) {
                ForEach(FeatherSigningOptions.InjectPath.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            Picker("Injection Folder", selection: $options.injectFolder) {
                ForEach(FeatherSigningOptions.InjectFolder.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            Toggle("Inject into Extensions", isOn: $options.injectIntoExtensions)
            Toggle("File Sharing", isOn: $options.fileSharing)
            Toggle("iTunes File Sharing", isOn: $options.iTunesFileSharing)
            Toggle("Pro Motion", isOn: $options.proMotion)
            Toggle("Game Mode", isOn: $options.gameMode)
            Toggle("iPad Fullscreen", isOn: $options.iPadFullscreen)
            Toggle("Remove URL Scheme", isOn: $options.removeURLScheme)
            Toggle("Remove Provisioning", isOn: $options.removeProvisioning)
            Toggle("Force Localize", isOn: $options.forceLocalize)
            Toggle("Enable Liquid Glass", isOn: $options.supportLiquidGlass)
            Toggle("Replace Substrate with ElleKit", isOn: $options.replaceSubstrateWithElleKit)
            Picker("Post Signing", selection: $options.postSigningAction) {
                ForEach(FeatherSigningOptions.PostSigningAction.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            Toggle("Delete After Signing", isOn: $options.deleteAfterSigning)

            Button("Reset Feather Options", role: .destructive) {
                options = .defaults
                options.save()
            }
        } header: {
            Text("Feather Options")
                .foregroundStyle(LitterTheme.textSecondary)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private var actionSection: some View {
        Section {
            Button {
                writePlanOnly()
            } label: {
                Label("Write Plan", systemImage: "doc.badge.plus")
            }
            .foregroundStyle(LitterTheme.accent)
            .disabled(isWorking)

            Button {
                startSigning()
            } label: {
                Label(isWorking ? "Signing..." : "Start Signing", systemImage: "signature")
            }
            .foregroundStyle(LitterTheme.accent)
            .disabled(isWorking || snapshot.importedIPA == nil)
        } header: {
            Text("Start")
                .foregroundStyle(LitterTheme.textSecondary)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func outputSection(_ text: String) -> some View {
        Section {
            Text(text)
                .litterMonoFont(size: 11, weight: .regular)
                .foregroundStyle(LitterTheme.textSecondary)
                .textSelection(.enabled)
        } header: {
            Text("Output")
                .foregroundStyle(LitterTheme.textSecondary)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func sourceRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .litterFont(.subheadline, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
            Text(detail)
                .litterMonoFont(size: 11, weight: .regular)
                .foregroundStyle(LitterTheme.textSecondary)
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func statusRow(_ title: String, value: String, ready: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ready ? LitterTheme.accent : LitterTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func fileCollectionRow(_ title: String, records: [FeatherSigningFileRecord], importAction: @escaping () -> Void, clearAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Spacer()
                Button("Import", action: importAction)
                    .litterFont(.caption)
                    .buttonStyle(.borderless)
                if !records.isEmpty {
                    Button("Clear", role: .destructive, action: clearAction)
                        .litterFont(.caption)
                        .buttonStyle(.borderless)
                }
            }
            if records.isEmpty {
                Text("None")
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
            } else {
                ForEach(records) { record in
                    Text(record.displayName)
                        .litterMonoFont(size: 11, weight: .regular)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func multilineField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .litterFont(.caption, weight: .semibold)
                .foregroundStyle(LitterTheme.textPrimary)
            TextField(prompt, text: text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...5)
        }
    }

    private func selectStagedURL(_ result: Result<[URL], Error>, allowedExtensions: Set<String>, label: String, assign: (URL) -> Void) {
        do {
            let selectedURL = try singleURL(from: result)
            try FeatherSigningMaterialStore.validateFileExtension(selectedURL, allowed: allowedExtensions, label: label)
            let stagedURL = try FeatherSigningMaterialStore.stageSelectionForLaterRead(from: selectedURL)
            assign(stagedURL)
        } catch {
            alert = SigningAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func importFile(_ result: Result<[URL], Error>, action: @escaping (URL) async throws -> FeatherSigningImportResult) {
        do {
            let url = try singleURL(from: result)
            isWorking = true
            Task {
                do {
                    let result = try await action(url)
                    await MainActor.run {
                        isWorking = false
                        refresh()
                        alert = SigningAlert(title: result.title, message: result.message)
                    }
                } catch {
                    await MainActor.run {
                        isWorking = false
                        alert = SigningAlert(title: "Import Failed", message: error.localizedDescription)
                    }
                }
            }
        } catch {
            alert = SigningAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func saveCertificate() {
        guard let p12URL, let profileURL else { return }
        isWorking = true
        Task {
            do {
                let result = try await FeatherSigningMaterialStore.importCertificate(
                    p12URL: p12URL,
                    provisioningProfileURL: profileURL,
                    password: p12Password,
                    nickname: certificateNickname
                )
                await MainActor.run {
                    isWorking = false
                    self.p12URL = nil
                    self.profileURL = nil
                    p12Password = ""
                    refresh()
                    alert = SigningAlert(title: result.title, message: result.message)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    alert = SigningAlert(title: "Certificate Rejected", message: error.localizedDescription)
                }
            }
        }
    }

    private func writePlanOnly() {
        do {
            let plan = try FeatherSigningMaterialStore.signingPlanJSON(options: options)
            isWorking = true
            Task {
                let path = await FeatherSigningMaterialStore.writeLatestPlan(plan)
                await MainActor.run {
                    isWorking = false
                    lastOutput = "Plan written: \(path ?? "fakefs write failed")\n\n" + plan
                }
            }
        } catch {
            alert = SigningAlert(title: "Plan Failed", message: error.localizedDescription)
        }
    }

    private func startSigning() {
        do {
            let plan = try FeatherSigningMaterialStore.signingPlanJSON(options: options)
            isWorking = true
            Task {
                let path = await FeatherSigningMaterialStore.writeLatestPlan(plan)
                let result = await LitterBuildKit.shared.signKittyStorePlan(planJSON: plan)
                await MainActor.run {
                    isWorking = false
                    refresh()
                    let artifacts = result.fakefsArtifacts.isEmpty ? "" : "\nArtifacts:\n" + result.fakefsArtifacts.joined(separator: "\n")
                    lastOutput = "Plan: \(path ?? "in-app only")\nStatus: \(result.status)\nExit: \(result.exitCode)\n\n\(result.log)\(artifacts)"
                }
            }
        } catch {
            alert = SigningAlert(title: "Signing Failed", message: error.localizedDescription)
        }
    }

    private func singleURL(from result: Result<[URL], Error>) throws -> URL {
        guard let url = try result.get().first else {
            throw NSError(domain: "FeatherSigningSettingsView", code: 64, userInfo: [NSLocalizedDescriptionKey: "No file was selected."])
        }
        return url
    }

    private func refresh() {
        snapshot = FeatherSigningMaterialStore.snapshot(checkRevocation: false)
    }

    private func openLocalDevVPN() {
        guard let url = URL(string: "localdevvpn://enable?scheme=sidestore") else { return }
        UIApplication.shared.open(url)
    }
}

private struct SigningAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

private extension UTType {
    static var litterP12: UTType { UTType(filenameExtension: "p12", conformingTo: .data) ?? UTType("com.rsa.pkcs-12") ?? .data }
    static var litterPFX: UTType { UTType(filenameExtension: "pfx", conformingTo: .data) ?? .data }
    static var litterMobileProvision: UTType { UTType(filenameExtension: "mobileprovision", conformingTo: .data) ?? UTType("com.apple.mobileprovision") ?? .data }
    static var litterProvisionProfile: UTType { UTType(filenameExtension: "provisionprofile", conformingTo: .data) ?? .data }
    static var litterPairing: UTType { UTType(filenameExtension: "pairing", conformingTo: .data) ?? .data }
    static var litterMobileDevicePairing: UTType { UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data) ?? UTType("com.apple.mobiledevicepairing") ?? .data }
    static var litterIPA: UTType { UTType(filenameExtension: "ipa", conformingTo: .data) ?? UTType("com.sigkitten.litter.ipa") ?? .data }
    static var litterEntitlements: UTType { UTType(filenameExtension: "entitlements", conformingTo: .data) ?? .data }
    static var litterDylib: UTType { UTType(filenameExtension: "dylib", conformingTo: .data) ?? .data }
    static var litterDeb: UTType { UTType(filenameExtension: "deb", conformingTo: .data) ?? .data }
    static var litterZip: UTType { UTType(filenameExtension: "zip", conformingTo: .data) ?? .data }
    static var litterFramework: UTType { UTType(filenameExtension: "framework", conformingTo: .folder) ?? .folder }
    static var litterPlugin: UTType { UTType(filenameExtension: "plugin", conformingTo: .folder) ?? .folder }
    static var litterAppeX: UTType { UTType(filenameExtension: "appex", conformingTo: .folder) ?? .folder }
}
