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
    @State private var activePicker: SigningFilePicker?
    @State private var isWorking = false
    @State private var lastOutput: String?
    @State private var alert: SigningAlert?
    @State private var pendingSignedInstall: PendingSignedInstall?
    @State private var isInstallPromptPresented = false
    @State private var signedIPAShareItem: FeatherSignedIPAShareItem?
    @State private var signedIPAInstallServer = FeatherSignedIPAInstallServer()

    private var missingItems: [String] {
        readinessMissing()
    }

    private var canStartSigning: Bool {
        !isWorking && snapshot.importedIPA != nil && missingItems.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Form {
                customizationSection
                signingSection
                advancedSection
                propertiesSection
                if let lastOutput, !lastOutput.isEmpty {
                    outputSection(lastOutput)
                }
                Color.clear
                    .frame(height: 86)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .disabled(isWorking)

            bottomSigningBar
        }
        .navigationTitle("Signing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    options = FeatherSigningOptions.defaults.normalizedForFeatherCertificate
                    options.save()
                    refresh()
                }
                .disabled(isWorking)
            }
        }
        .sheet(item: $activePicker) { picker in
            SigningFilePickerSheet(
                allowedContentTypes: picker.allowedContentTypes,
                allowsMultipleSelection: picker.allowsMultipleSelection
            ) { urls in
                activePicker = nil
                handlePicked(urls, for: picker)
            }
            .ignoresSafeArea()
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Signed IPA Ready", isPresented: $isInstallPromptPresented, titleVisibility: .visible) {
            if let pendingSignedInstall {
                Button("Install Signed IPA") {
                    installSignedArtifact(pendingSignedInstall)
                }
            }
            Button("Keep File", role: .cancel) {
                pendingSignedInstall = nil
            }
        } message: {
            if let pendingSignedInstall {
                Text(pendingSignedInstall.ipaPath)
            } else {
                Text("The signed IPA was created.")
            }
        }
        .sheet(item: $signedIPAShareItem) { item in
            FeatherSignedIPAActivitySheet(activityItems: [item.url])
        }
        .task {
            options = options.normalizedForFeatherCertificate
            refresh()
        }
        .onDisappear { options.save() }
        .onChange(of: options) { _, newValue in newValue.normalizedForFeatherCertificate.save() }
    }

    private var customizationSection: some View {
        featherSection("Customization") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    appIconPreview

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.importedIPA?.appName ?? snapshot.importedIPA?.displayName ?? "No IPA Selected")
                            .font(.headline)
                            .lineLimit(2)
                        Text(importedIPASubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                }

                pickerButton(
                    title: snapshot.importedIPA == nil ? "Import Application" : "Replace Application",
                    subtitle: snapshot.importedIPA?.displayName,
                    systemImage: "square.and.arrow.down",
                    picker: .ipa
                )
            }

            LabeledContent("Name") {
                TextField("Keep Original", text: $options.appName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            LabeledContent("Identifier") {
                TextField("Keep Original", text: $options.bundleIdentifier)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledContent("Version") {
                TextField("Keep Original", text: $options.appVersion)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var signingSection: some View {
        featherSection("Signing") {
            if snapshot.certificateState.isUsable {
                certificateCard
            } else {
                Text("No Certificate")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            pickerButton(
                title: p12URL == nil ? "Import Certificate File" : "Certificate File",
                subtitle: p12URL?.lastPathComponent,
                systemImage: "key.fill",
                picker: .p12
            )

            pickerButton(
                title: profileURL == nil ? "Import Provisioning File" : "Provisioning File",
                subtitle: profileURL?.lastPathComponent,
                systemImage: "doc.badge.gearshape",
                picker: .profile
            )

            SecureField("Certificate Password", text: $p12Password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Nickname (Optional)", text: $certificateNickname)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                saveCertificate()
            } label: {
                Label("Save Certificate", systemImage: "checkmark.seal.fill")
            }
            .disabled(p12URL == nil || profileURL == nil || isWorking)

            if snapshot.certificate != nil || snapshot.provisioningProfile != nil {
                Button(role: .destructive) {
                    FeatherSigningMaterialStore.clearCertificate()
                    refresh()
                } label: {
                    Label("Clear Certificate", systemImage: "trash")
                }
            }

            Picker("Signing Type", selection: $options.signingType) {
                ForEach(FeatherSigningOptions.SigningType.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
        } footer: {
            Text("Feather signing uses the saved .p12/.pfx and matching .mobileprovision. Apple ID signing stays in KittyStore.")
        }
    }

    private var advancedSection: some View {
        featherSection("Advanced") {
            DisclosureGroup("Modify") {
                fileCollectionRow("Existing Dylibs", records: snapshot.dylibs, picker: .dylib, clearAction: {
                    FeatherSigningMaterialStore.clearDylibs(); refresh()
                })
                multilineField("Remove Dylibs", text: $options.removeDylibsText, prompt: "@executable_path/Old.dylib")
                fileCollectionRow("Frameworks & PlugIns", records: snapshot.frameworksAndPlugins, picker: .framework, clearAction: {
                    FeatherSigningMaterialStore.clearFrameworksAndPlugins(); refresh()
                })
                fileCollectionRow("Tweaks", records: snapshot.tweaks, picker: .tweak, clearAction: {
                    FeatherSigningMaterialStore.clearTweaks(); refresh()
                })
                pickerButton(
                    title: snapshot.entitlements == nil ? "Import Entitlements" : "Entitlements",
                    subtitle: snapshot.entitlements?.displayName,
                    systemImage: "doc.text",
                    picker: .entitlements
                )
                if snapshot.entitlements != nil {
                    Button(role: .destructive) {
                        FeatherSigningMaterialStore.clearEntitlements(); refresh()
                    } label: {
                        Label("Clear Entitlements", systemImage: "trash")
                    }
                }
            }

            DisclosureGroup("Properties") {
                multilineField("Remove Files", text: $options.removeFilesText, prompt: "Frameworks/CydiaSubstrate.framework")
                multilineField("Properties", text: $options.customPropertiesText, prompt: "key=value")
            }
        }
    }

    private var propertiesSection: some View {
        featherSection("Options") {
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
        }
    }

    private var bottomSigningBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 18)

            VStack(spacing: 8) {
                if !missingItems.isEmpty {
                    Text("Missing: " + missingItems.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                Button {
                    startSigning()
                } label: {
                    SheetButton(title: isWorking ? "Signing..." : "Start Signing", systemImage: "signature", isWorking: isWorking)
                }
                .buttonStyle(.plain)
                .disabled(!canStartSigning)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(.ultraThinMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var appIconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
            if let iconPath = snapshot.importedIPA?.iconAppPath,
               let icon = UIImage(contentsOfFile: iconPath) {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        }
    }

    private var importedIPASubtitle: String {
        guard let record = snapshot.importedIPA else { return "Import an .ipa or .tipa before signing" }
        let version = [record.appVersion, record.buildVersion]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let details = [record.bundleIdentifier, version]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return details.isEmpty ? record.shortDetail : details.joined(separator: " - ")
    }

    private var certificateCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.certificate?.displayName ?? "Saved Certificate")
                    .font(.subheadline.weight(.semibold))
                Text(snapshot.certificateState.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func outputSection(_ text: String) -> some View {
        featherSection("Output") {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func featherSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.top, 8)
        }
        .headerProminence(.increased)
    }

    private func featherSection<Content: View, Footer: View>(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) -> some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.top, 8)
        } footer: {
            footer()
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .headerProminence(.increased)
    }

    private func pickerButton(title: String, subtitle: String?, systemImage: String, picker: SigningFilePicker) -> some View {
        Button {
            activePicker = picker
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func statusRow(_ title: String, value: String, ready: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.headline)
                .foregroundStyle(ready ? Color.accentColor : Color.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func fileCollectionRow(_ title: String, records: [FeatherSigningFileRecord], picker: SigningFilePicker, clearAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Import") { activePicker = picker }
                    .buttonStyle(.borderless)
                if !records.isEmpty {
                    Button("Clear", role: .destructive, action: clearAction)
                        .buttonStyle(.borderless)
                }
            }

            if records.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    Text(record.displayName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func multilineField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            TextField(prompt, text: text, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(2...5)
        }
    }

    private func handlePicked(_ urls: [URL], for picker: SigningFilePicker) {
        guard let url = urls.first else { return }
        switch picker {
        case .p12:
            selectStagedURL(url, allowedExtensions: ["p12", "pfx"], label: "certificate", assign: { p12URL = $0 })
        case .profile:
            selectStagedURL(url, allowedExtensions: ["mobileprovision", "provisionprofile"], label: "provisioning profile", assign: { profileURL = $0 })
        case .pairing:
            importFile(url) { try await FeatherSigningMaterialStore.importPairingFile(from: $0) }
        case .ipa:
            importFile(url) { try await FeatherSigningMaterialStore.importIPA(from: $0) }
        case .entitlements:
            importFile(url) { try await FeatherSigningMaterialStore.importEntitlements(from: $0) }
        case .dylib:
            importFile(url) { try await FeatherSigningMaterialStore.importDylib(from: $0) }
        case .framework:
            importFile(url) { try await FeatherSigningMaterialStore.importFrameworkOrPlugin(from: $0) }
        case .tweak:
            importFile(url) { try await FeatherSigningMaterialStore.importTweak(from: $0) }
        }
    }

    private func selectStagedURL(_ url: URL, allowedExtensions: Set<String>, label: String, assign: (URL) -> Void) {
        do {
            try FeatherSigningMaterialStore.validateFileExtension(url, allowed: allowedExtensions, label: label)
            let stagedURL = try FeatherSigningMaterialStore.stageSelectionForLaterRead(from: url)
            assign(stagedURL)
        } catch {
            alert = SigningAlert(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func importFile(_ url: URL, action: @escaping (URL) async throws -> FeatherSigningImportResult) {
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
                    certificateNickname = ""
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

    private func startSigning() {
        isWorking = true
        Task {
            do {
                let normalizedOptions = options.normalizedForFeatherCertificate
                let plan = try FeatherSigningMaterialStore.signingPlanJSON(options: normalizedOptions)
                let path = await FeatherSigningMaterialStore.writeLatestPlan(plan)
                let result = await FeatherSigningMaterialStore.signImportedIPA(options: normalizedOptions)
                await MainActor.run {
                    options = normalizedOptions
                    isWorking = false
                    refresh()
                    let artifact = result.signedIPAFakefsPath.map { "\nArtifact:\n\($0)" } ?? ""
                    lastOutput = "Plan: \(path ?? "in-app only")\nStatus: \(result.status)\nExit: \(result.exitCode)\n\n\(result.log)\(artifact)"
                    if result.exitCode == 0, let appPath = result.signedIPAAppPath {
                        let pending = PendingSignedInstall(
                            ipaPath: appPath,
                            bundleIdentifier: result.bundleIdentifier
                        )
                        pendingSignedInstall = pending
                        isInstallPromptPresented = true
                    }
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    alert = SigningAlert(title: "Signing Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private var resolvedPendingBundleIdentifier: String {
        let explicit = options.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        return snapshot.importedIPA?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func installSignedArtifact(_ pending: PendingSignedInstall) {
        isInstallPromptPresented = false
        pendingSignedInstall = nil
        guard let url = FeatherSigningMaterialStore.signedIPAURL(appPath: pending.ipaPath) else {
            alert = SigningAlert(title: "Signed IPA Missing", message: "The signed IPA could not be found at \(pending.ipaPath).")
            return
        }
        let appName = snapshot.importedIPA?.appName ?? snapshot.importedIPA?.displayName ?? url.deletingPathExtension().lastPathComponent
        let appVersion = snapshot.importedIPA?.appVersion ?? "1.0"
        let iconURL = snapshot.importedIPA?.iconAppPath.map { URL(fileURLWithPath: $0) }
        do {
            let installURL = try signedIPAInstallServer.start(
                payloadURL: url,
                bundleIdentifier: pending.bundleIdentifier,
                appName: appName,
                appVersion: appVersion,
                iconURL: iconURL
            )
            lastOutput = "Feather install server ready\nBundle ID: \(pending.bundleIdentifier)\nPath: \(url.path)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                UIApplication.shared.open(installURL) { success in
                    if !success {
                        signedIPAShareItem = FeatherSignedIPAShareItem(url: url)
                        alert = SigningAlert(title: "Install Link Blocked", message: "iOS did not open the Feather install link. The signed IPA share sheet is open as a fallback.")
                    }
                }
            }
        } catch {
            signedIPAShareItem = FeatherSignedIPAShareItem(url: url)
            alert = SigningAlert(title: "Install Server Failed", message: "\(error.localizedDescription)\n\nThe signed IPA share sheet is open as a fallback.")
        }
    }

    private func refresh() {
        snapshot = FeatherSigningMaterialStore.snapshot(checkRevocation: false)
    }

    private func readinessMissing() -> [String] {
        var missing: [String] = []
        if snapshot.importedIPA == nil { missing.append("IPA") }
        if snapshot.importedIPA != nil, resolvedPendingBundleIdentifier.isEmpty { missing.append("bundle identifier") }
        if !snapshot.certificateState.isUsable { missing.append("certificate") }
        if snapshot.provisioningProfile == nil { missing.append("provisioning profile") }
        var unique: [String] = []
        for item in missing where !unique.contains(item) {
            unique.append(item)
        }
        return unique
    }
}

private struct PendingSignedInstall: Identifiable {
    let id = UUID()
    var ipaPath: String
    var bundleIdentifier: String
}

private enum SigningFilePicker: String, Identifiable {
    case p12
    case profile
    case pairing
    case ipa
    case entitlements
    case dylib
    case framework
    case tweak

    var id: String { rawValue }

    var allowedContentTypes: [UTType] {
        switch self {
        case .p12:
            return [.litterP12, .litterPFX, .data]
        case .profile:
            return [.litterMobileProvision, .litterProvisionProfile, .data]
        case .pairing:
            return [.litterPairing, .litterMobileDevicePairing, .propertyList, .data]
        case .ipa:
            return [.litterIPA, .zip, .data]
        case .entitlements:
            return [.litterEntitlements, .propertyList, .xml, .data]
        case .dylib:
            return [.litterDylib, .data]
        case .framework:
            return [.folder, .litterFramework, .litterPlugin, .litterAppeX]
        case .tweak:
            return [.litterDeb, .litterDylib, .litterZip, .data]
        }
    }

    var allowsMultipleSelection: Bool { false }
}

private struct SigningFilePickerSheet: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var allowsMultipleSelection = false
    var onDocumentsPicked: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsPicked: onDocumentsPicked)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onDocumentsPicked: ([URL]) -> Void

        init(onDocumentsPicked: @escaping ([URL]) -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDocumentsPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDocumentsPicked([])
        }
    }
}

private struct SheetButton: View {
    var title: String
    var systemImage: String
    var isWorking: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            if isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.headline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(isEnabled ? Color.accentColor : Color(uiColor: .quaternarySystemFill))
        .foregroundStyle(isEnabled ? Color.white : Color.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FeatherSignedIPAShareItem: Identifiable {
    let id = UUID()
    var url: URL
}

private struct FeatherSignedIPAActivitySheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
