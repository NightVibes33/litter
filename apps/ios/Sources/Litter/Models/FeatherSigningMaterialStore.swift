import Foundation

struct FeatherSigningFileRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var appPath: String
    var fakefsPath: String
    var byteCount: Int64
    var importedAt: Date
    var detail: String

    var shortDetail: String {
        if !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return detail }
        if byteCount > 0 { return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file) }
        return fakefsPath
    }
}

struct FeatherSigningMaterialSnapshot: Equatable, Sendable {
    var certificate: FeatherSigningFileRecord?
    var provisioningProfile: FeatherSigningFileRecord?
    var pairingFile: FeatherSigningFileRecord?
    var importedIPA: FeatherSigningFileRecord?
    var entitlements: FeatherSigningFileRecord?
    var dylibs: [FeatherSigningFileRecord]
    var frameworksAndPlugins: [FeatherSigningFileRecord]
    var tweaks: [FeatherSigningFileRecord]
    var certificateState: NyxianSigningCertificateState
    var localDevVPNState: NyxianLocalDevVPNState
}

struct FeatherSigningImportResult: Sendable {
    var title: String
    var message: String
}

struct FeatherSigningOptions: Codable, Equatable, Sendable {
    enum SigningMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case certificate = "certificate"
        case appleID = "apple-id"
        var id: String { rawValue }
        var label: String { self == .certificate ? "Certificate" : "Apple ID" }
    }

    enum SigningType: String, Codable, CaseIterable, Identifiable, Sendable {
        case `default` = "default"
        case force = "force"
        case adhoc = "adhoc"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .default: return "Default"
            case .force: return "Modify"
            case .adhoc: return "Ad Hoc"
            }
        }
    }

    enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
        case `default` = "default"
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }
        var label: String { rawValue == "default" ? "Default" : rawValue }
    }

    enum MinimumRequirement: String, Codable, CaseIterable, Identifiable, Sendable {
        case `default` = "default"
        case v16 = "16.0"
        case v15 = "15.0"
        case v14 = "14.0"
        case v13 = "13.0"
        case v12 = "12.0"
        var id: String { rawValue }
        var label: String { rawValue == "default" ? "Default" : rawValue }
    }

    enum InjectPath: String, Codable, CaseIterable, Identifiable, Sendable {
        case executablePath = "@executable_path"
        case rpath = "@rpath"
        var id: String { rawValue }
        var label: String { rawValue }
    }

    enum InjectFolder: String, Codable, CaseIterable, Identifiable, Sendable {
        case root = "/"
        case frameworks = "/Frameworks/"
        var id: String { rawValue }
        var label: String { rawValue }
    }

    enum PostSigningAction: String, Codable, CaseIterable, Identifiable, Sendable {
        case none
        case install
        case refresh
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "None"
            case .install: return "Install"
            case .refresh: return "Refresh"
            }
        }
    }

    var signingMode: SigningMode = .certificate
    var signingType: SigningType = .default
    var appName: String = ""
    var bundleIdentifier: String = ""
    var appVersion: String = ""
    var appAppearance: AppAppearance = .default
    var minimumRequirement: MinimumRequirement = .default
    var injectPath: InjectPath = .executablePath
    var injectFolder: InjectFolder = .frameworks
    var injectIntoExtensions = false
    var fileSharing = false
    var iTunesFileSharing = false
    var proMotion = false
    var gameMode = false
    var iPadFullscreen = false
    var removeURLScheme = false
    var removeProvisioning = false
    var forceLocalize = false
    var supportLiquidGlass = false
    var replaceSubstrateWithElleKit = false
    var removeDylibsText = ""
    var removeFilesText = ""
    var customPropertiesText = ""
    var postSigningAction: PostSigningAction = .none
    var deleteAfterSigning = false

    static let defaults = FeatherSigningOptions()

    static func load() -> FeatherSigningOptions {
        guard let data = UserDefaults.standard.data(forKey: FeatherSigningMaterialStore.optionsKey),
              let options = try? JSONDecoder().decode(FeatherSigningOptions.self, from: data) else {
            return .defaults
        }
        return options
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: FeatherSigningMaterialStore.optionsKey)
    }
}

enum FeatherSigningMaterialStore {
    static let optionsKey = "signing_options"
    private static let certificateRecordKey = "litter.feather.signing.certificate.record.v1"
    private static let provisioningProfileRecordKey = "litter.feather.signing.mobileprovision.record.v1"
    private static let pairingRecordKey = "litter.feather.signing.pairing.record.v1"
    private static let importedIPARecordKey = "litter.feather.signing.ipa.record.v1"
    private static let entitlementsRecordKey = "litter.feather.signing.entitlements.record.v1"
    private static let dylibsRecordKey = "litter.feather.signing.dylibs.records.v1"
    private static let frameworksRecordKey = "litter.feather.signing.frameworks.records.v1"
    private static let tweaksRecordKey = "litter.feather.signing.tweaks.records.v1"
    private static let profileSummaryKey = "litter.feather.signing.mobileprovision.summary.v1"

    static var documentsRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
    }

    static var certificatesRoot: URL { documentsRoot.appendingPathComponent("Certificates", isDirectory: true) }
    static var featherPairingURL: URL { documentsRoot.appendingPathComponent("pairingFile.plist", isDirectory: false) }
    static var sideStorePairingURL: URL { documentsRoot.appendingPathComponent("ALTPairingFile.mobiledevicepairing", isDirectory: false) }
    private static var workspaceRoot: URL { documentsRoot.appendingPathComponent("FeatherSigning", isDirectory: true) }

    static func stageSelectionForLaterRead(from url: URL) throws -> URL {
        let data = try readSecurityScopedData(from: url)
        let safeName = sanitizedFileName(url.lastPathComponent, fallback: "selected-file")
        let destination = workspaceRoot
            .appendingPathComponent("StagedSelections", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(safeName, isDirectory: false)
        try writeReplacing(data, to: destination)
        return destination
    }

    static func validateFileExtension(_ url: URL, allowed: Set<String>, label: String) throws {
        try requireExtension(url, allowed: allowed, label: label)
    }

    static func snapshot(checkRevocation: Bool = true) -> FeatherSigningMaterialSnapshot {
        FeatherSigningMaterialSnapshot(
            certificate: loadRecord(certificateRecordKey),
            provisioningProfile: loadRecord(provisioningProfileRecordKey),
            pairingFile: loadPairingRecord(),
            importedIPA: loadRecord(importedIPARecordKey),
            entitlements: loadRecord(entitlementsRecordKey),
            dylibs: loadRecords(dylibsRecordKey),
            frameworksAndPlugins: loadRecords(frameworksRecordKey),
            tweaks: loadRecords(tweaksRecordKey),
            certificateState: NyxianSigningCertificateStorage.savedState(checkRevocation: checkRevocation),
            localDevVPNState: NyxianLocalDevVPNDetector.currentState()
        )
    }

    static func importCertificate(p12URL: URL, provisioningProfileURL: URL, password: String, nickname: String) async throws -> FeatherSigningImportResult {
        try requireExtension(p12URL, allowed: ["p12", "pfx"], label: "certificate")
        try requireExtension(provisioningProfileURL, allowed: ["mobileprovision", "provisionprofile"], label: "provisioning profile")
        let p12Data = try readSecurityScopedData(from: p12URL)
        let profileData = try readSecurityScopedData(from: provisioningProfileURL)
        let certificateSummary = try NyxianSigningCertificateValidator.validate(pkcs12Data: p12Data, password: password, checkRevocation: false)
        let profileSummary = try NyxianProvisioningProfileValidator.validate(data: profileData, signingCertificateFingerprint: certificateSummary.sha256Fingerprint)

        let uuid = UUID().uuidString
        let directory = certificatesRoot.appendingPathComponent(uuid, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let p12Name = sanitizedFileName(p12URL.lastPathComponent, fallback: "certificate.p12")
        let profileName = sanitizedFileName(provisioningProfileURL.lastPathComponent, fallback: "profile.mobileprovision")
        let p12Destination = directory.appendingPathComponent(p12Name, isDirectory: false)
        let profileDestination = directory.appendingPathComponent(profileName, isDirectory: false)
        try writeReplacing(p12Data, to: p12Destination)
        try writeReplacing(profileData, to: profileDestination)

        let fakefsDirectory = "/root/.litter/kittystore/certificates/\(uuid)"
        let fakefsP12 = "\(fakefsDirectory)/\(p12Name)"
        let fakefsProfile = "\(fakefsDirectory)/\(profileName)"
        var warnings: [String] = []
        if let warning = await stageFakefsFile(data: p12Data, path: fakefsP12) { warnings.append(warning) }
        if let warning = await stageFakefsFile(data: profileData, path: fakefsProfile) { warnings.append(warning) }

        NyxianSigningCertificateStorage.save(data: p12Data, password: password, summary: certificateSummary)
        saveRecord(FeatherSigningFileRecord(id: uuid, displayName: nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? certificateSummary.commonName : nickname, appPath: p12Destination.path, fakefsPath: fakefsP12, byteCount: Int64(p12Data.count), importedAt: Date(), detail: certificateSummary.statusDetail), key: certificateRecordKey)
        saveRecord(FeatherSigningFileRecord(id: uuid, displayName: profileSummary.name, appPath: profileDestination.path, fakefsPath: fakefsProfile, byteCount: Int64(profileData.count), importedAt: Date(), detail: profileSummary.statusDetail), key: provisioningProfileRecordKey)
        if let encoded = try? JSONEncoder().encode(profileSummary) { UserDefaults.standard.set(encoded, forKey: profileSummaryKey) }

        let warningText = warnings.isEmpty ? "" : "\n\nFakefs staging warning:\n" + warnings.joined(separator: "\n")
        return FeatherSigningImportResult(title: "Certificate Saved", message: "\(certificateSummary.importMessage)\n\(profileSummary.importMessage)\(warningText)")
    }

    static func clearCertificate() {
        NyxianSigningCertificateStorage.clear()
        UserDefaults.standard.removeObject(forKey: certificateRecordKey)
        UserDefaults.standard.removeObject(forKey: provisioningProfileRecordKey)
        UserDefaults.standard.removeObject(forKey: profileSummaryKey)
    }

    static func importPairingFile(from url: URL) async throws -> FeatherSigningImportResult {
        try requireExtension(url, allowed: ["mobiledevicepairing", "pairing", "plist"], label: "pairing file")
        let normalizedData = try normalizedPairingData(readSecurityScopedData(from: url))
        try FileManager.default.createDirectory(at: documentsRoot, withIntermediateDirectories: true)
        try writeReplacing(normalizedData, to: featherPairingURL)
        try writeReplacing(normalizedData, to: sideStorePairingURL)
        let fakefsPath = "/root/.litter/kittystore/pairing/ALTPairingFile.mobiledevicepairing"
        let warning = await stageFakefsFile(data: normalizedData, path: fakefsPath)
        let detail = pairingRecordDetail(data: normalizedData)
        let record = FeatherSigningFileRecord(id: UUID().uuidString, displayName: sanitizedFileName(url.lastPathComponent, fallback: "ALTPairingFile.mobiledevicepairing"), appPath: sideStorePairingURL.path, fakefsPath: fakefsPath, byteCount: Int64(normalizedData.count), importedAt: Date(), detail: detail)
        saveRecord(record, key: pairingRecordKey)
        return FeatherSigningImportResult(title: "Pairing File Saved", message: "Saved \(record.displayName) to KittyStore and Feather document paths.\n\(detail)" + (warning.map { "\n\nFakefs staging warning:\n\($0)" } ?? ""))
    }

    static func importIPA(from url: URL) async throws -> FeatherSigningImportResult {
        let record = try await importFile(from: url, allowedExtensions: ["ipa", "tipa"], label: "IPA", appSubdirectory: "Unsigned", fakefsSubdirectory: "imports", recordKey: importedIPARecordKey, append: false)
        return FeatherSigningImportResult(title: "IPA Imported", message: "\(record.displayName)\n\(record.fakefsPath)")
    }

    static func importEntitlements(from url: URL) async throws -> FeatherSigningImportResult {
        let record = try await importFile(from: url, allowedExtensions: ["entitlements", "plist", "xml"], label: "entitlements", appSubdirectory: "Entitlements", fakefsSubdirectory: "entitlements", recordKey: entitlementsRecordKey, append: false)
        return FeatherSigningImportResult(title: "Entitlements Imported", message: "\(record.displayName)\n\(record.fakefsPath)")
    }

    static func importDylib(from url: URL) async throws -> FeatherSigningImportResult {
        let record = try await importFile(from: url, allowedExtensions: ["dylib"], label: "dylib", appSubdirectory: "Dylibs", fakefsSubdirectory: "dylibs", recordKey: dylibsRecordKey, append: true)
        return FeatherSigningImportResult(title: "Dylib Imported", message: "\(record.displayName)\n\(record.fakefsPath)")
    }

    static func importFrameworkOrPlugin(from url: URL) async throws -> FeatherSigningImportResult {
        let record = try await importFile(from: url, allowedExtensions: ["framework", "appex", "bundle", "plugin"], label: "framework/plugin", appSubdirectory: "Frameworks", fakefsSubdirectory: "frameworks", recordKey: frameworksRecordKey, append: true, allowDirectory: true)
        return FeatherSigningImportResult(title: "Framework Imported", message: "\(record.displayName)\n\(record.fakefsPath)")
    }

    static func importTweak(from url: URL) async throws -> FeatherSigningImportResult {
        let record = try await importFile(from: url, allowedExtensions: ["deb", "dylib", "zip"], label: "tweak", appSubdirectory: "Tweaks", fakefsSubdirectory: "tweaks", recordKey: tweaksRecordKey, append: true)
        return FeatherSigningImportResult(title: "Tweak Imported", message: "\(record.displayName)\n\(record.fakefsPath)")
    }

    static func clearImportedIPA() { UserDefaults.standard.removeObject(forKey: importedIPARecordKey) }
    static func clearEntitlements() { UserDefaults.standard.removeObject(forKey: entitlementsRecordKey) }
    static func clearDylibs() { UserDefaults.standard.removeObject(forKey: dylibsRecordKey) }
    static func clearFrameworksAndPlugins() { UserDefaults.standard.removeObject(forKey: frameworksRecordKey) }
    static func clearTweaks() { UserDefaults.standard.removeObject(forKey: tweaksRecordKey) }

    static func signingPlanJSON(options: FeatherSigningOptions) throws -> String {
        let snapshot = snapshot(checkRevocation: false)
        let customProperties = keyValueLines(options.customPropertiesText).reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = entry.value
        }
        let removeDylibs = lines(options.removeDylibsText)
        let removeFiles = lines(options.removeFilesText)
        let properties = FeatherSigningUpstreamAdapter.properties(options: options, customProperties: customProperties)
        let featherOptions = FeatherSigningUpstreamAdapter.optionsPayload(
            appName: options.appName,
            appVersion: options.appVersion,
            appIdentifier: options.bundleIdentifier,
            entitlementsFile: snapshot.entitlements?.fakefsPath ?? "",
            signingType: options.signingType.rawValue,
            injectionFiles: snapshot.dylibs.map(\.fakefsPath) + snapshot.tweaks.map(\.fakefsPath),
            frameworkAndPluginFiles: snapshot.frameworksAndPlugins.map(\.fakefsPath),
            disInjectionFiles: removeDylibs,
            removeFiles: removeFiles,
            properties: properties
        )

        let plan: [String: Any] = [
            "schemaVersion": 1,
            "kind": "KittyStoreSigningPlan",
            "mode": options.signingMode.rawValue,
            "sourceURL": AppReleaseSource.current.stableSourceURLString,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "app": ["name": options.appName, "bundleIdentifier": options.bundleIdentifier, "version": options.appVersion, "ipa": snapshot.importedIPA?.fakefsPath ?? ""],
            "signing": [
                "type": options.signingType.rawValue,
                "certificateReady": snapshot.certificateState.isUsable,
                "certificateDetail": snapshot.certificateState.statusDetail,
                "provisioningProfile": snapshot.provisioningProfile?.fakefsPath ?? "embedded",
                "appleIDReady": NyxianAppleIDStore.isLoggedIn,
                "appleIDDetail": NyxianAppleIDStore.load()?.statusDetail ?? "Missing",
                "pairingFile": snapshot.pairingFile?.fakefsPath ?? "",
                "localDevVPNReady": snapshot.localDevVPNState.isConnected,
                "localDevVPNDetail": snapshot.localDevVPNState.detail
            ],
            "modify": [
                "existingDylibs": snapshot.dylibs.map(\.fakefsPath),
                "removeDylibs": removeDylibs,
                "removeFiles": removeFiles,
                "frameworksAndPlugins": snapshot.frameworksAndPlugins.map(\.fakefsPath),
                "tweaks": snapshot.tweaks.map(\.fakefsPath),
                "entitlements": snapshot.entitlements.flatMap { try? String(contentsOfFile: $0.appPath, encoding: .utf8) } ?? ""
            ],
            "properties": properties,
            "featherOptions": featherOptions,
            "upstream": FeatherSigningUpstreamAdapter.provenance(),
            "readiness": ["ready": snapshot.importedIPA != nil, "missing": readinessMissing(snapshot: snapshot, options: options)]
        ]
        let data = try JSONSerialization.data(withJSONObject: plan, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "FeatherSigningMaterialStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode signing plan."])
        }
        return text + "\n"
    }

    static func preparePairingFakefsIfNeeded() async -> String? {
        guard let record = loadPairingRecord() else { return nil }
        guard FileManager.default.fileExists(atPath: record.appPath) else { return "Pairing source is missing: \(record.appPath)" }
        if await IshFS.exists(path: record.fakefsPath) { return nil }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: record.appPath))
            return await stageFakefsFile(data: data, path: record.fakefsPath)
        } catch {
            return "\(record.fakefsPath): \(error.localizedDescription)"
        }
    }

    static func writeLatestPlan(_ plan: String) async -> String? {
        let path = "/root/.litter/kittystore/plans/latest.json"
        do {
            try await IshFS.createDirectoryIfNeeded(path: "/root/.litter/kittystore/plans")
            try await IshFS.writeTextFile(path: path, text: plan)
            return path
        } catch {
            return nil
        }
    }

    private static func importFile(from url: URL, allowedExtensions: Set<String>, label: String, appSubdirectory: String, fakefsSubdirectory: String, recordKey: String, append: Bool, allowDirectory: Bool = false) async throws -> FeatherSigningFileRecord {
        let isDirectory = try resourceIsDirectoryScoped(url)
        if isDirectory {
            guard allowDirectory else { throw NSError(domain: "FeatherSigningMaterialStore", code: 64, userInfo: [NSLocalizedDescriptionKey: "Select a \(label) file, not a folder."]) }
        } else {
            try requireExtension(url, allowed: allowedExtensions, label: label)
        }
        let uuid = UUID().uuidString
        let safeName = sanitizedFileName(url.lastPathComponent, fallback: "\(label)-\(uuid)")
        let destinationRoot = workspaceRoot.appendingPathComponent(appSubdirectory, isDirectory: true).appendingPathComponent(uuid, isDirectory: true)
        let destination = destinationRoot.appendingPathComponent(safeName, isDirectory: isDirectory)
        try copySecurityScopedItem(from: url, to: destination)
        let fakefsPath = "/root/.litter/kittystore/\(fakefsSubdirectory)/\(uuid)/\(safeName)"
        let warning = await stageFakefsItem(from: destination, to: fakefsPath)
        let record = FeatherSigningFileRecord(id: uuid, displayName: safeName, appPath: destination.path, fakefsPath: fakefsPath, byteCount: itemSize(destination), importedAt: Date(), detail: warning ?? "Imported")
        if append {
            var records = loadRecords(recordKey)
            records.append(record)
            saveRecords(records, key: recordKey)
        } else {
            saveRecord(record, key: recordKey)
        }
        return record
    }

    private static func readinessMissing(snapshot: FeatherSigningMaterialSnapshot, options: FeatherSigningOptions) -> [String] {
        var missing: [String] = []
        if snapshot.importedIPA == nil { missing.append("IPA") }
        switch options.signingMode {
        case .certificate:
            if !snapshot.certificateState.isUsable { missing.append("validated .p12 certificate") }
            if snapshot.provisioningProfile == nil, options.signingType != .adhoc { missing.append(".mobileprovision profile") }
        case .appleID:
            if !NyxianAppleIDStore.isLoggedIn { missing.append("Apple ID login") }
            if snapshot.pairingFile == nil { missing.append("pairing file") }
            if !snapshot.localDevVPNState.isConnected { missing.append("LocalDevVPN") }
        }
        if options.postSigningAction != .none {
            if snapshot.pairingFile == nil { missing.append("pairing file for install/refresh") }
            if !snapshot.localDevVPNState.isConnected { missing.append("LocalDevVPN for install/refresh") }
        }
        return missing
    }

    private static func loadPairingRecord() -> FeatherSigningFileRecord? {
        if let record = loadRecord(pairingRecordKey) { return record }
        let fileManager = FileManager.default
        let candidates = [sideStorePairingURL, featherPairingURL]
        guard let url = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else { return nil }
        let attributes = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let importedAt = (attributes[.modificationDate] as? Date) ?? Date()
        let detail = (try? Data(contentsOf: url)).map(pairingRecordDetail(data:)) ?? "Imported in KittyStore Settings"
        let record = FeatherSigningFileRecord(
            id: "kittystore-pairing-file",
            displayName: url.lastPathComponent,
            appPath: url.path,
            fakefsPath: "/root/.litter/kittystore/pairing/ALTPairingFile.mobiledevicepairing",
            byteCount: byteCount,
            importedAt: importedAt,
            detail: detail
        )
        saveRecord(record, key: pairingRecordKey)
        return record
    }

    private static func loadRecord(_ key: String) -> FeatherSigningFileRecord? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FeatherSigningFileRecord.self, from: data)
    }

    private static func saveRecord(_ record: FeatherSigningFileRecord, key: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadRecords(_ key: String) -> [FeatherSigningFileRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FeatherSigningFileRecord].self, from: data)) ?? []
    }

    private static func saveRecords(_ records: [FeatherSigningFileRecord], key: String) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func readSecurityScopedData(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private static func copySecurityScopedItem(from url: URL, to destination: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: url, to: destination)
    }

    private static func writeReplacing(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
    }

    private static func requireExtension(_ url: URL, allowed: Set<String>, label: String) throws {
        let ext = url.pathExtension.lowercased()
        guard allowed.contains(ext) else {
            throw NSError(domain: "FeatherSigningMaterialStore", code: 64, userInfo: [NSLocalizedDescriptionKey: "Select a \(label) file with one of these extensions: \(allowed.sorted().joined(separator: ", "))."])
        }
    }


    private static func pairingRecordDetail(data: Data) -> String {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dictionary = plist as? [String: Any] {
            return pairingRecordDetail(dictionary: dictionary)
        }
        if let text = String(data: data, encoding: .utf8), isValidPairingText(text) {
            if lockdownPairingKeys.allSatisfy({ text.contains($0) }) {
                return "Lockdown pairing file imported (UDID present)"
            }
            if remotePairingKeys.allSatisfy({ text.contains($0) }) {
                return "Remote pairing file imported"
            }
        }
        return "Pairing file imported"
    }

    private static func pairingRecordDetail(dictionary: [String: Any]) -> String {
        let keys = Set(dictionary.keys)
        let hasLockdownRecord = lockdownPairingKeys.isSubset(of: keys)
        let hasRemotePairingRecord = remotePairingKeys.isSubset(of: keys)
        if hasLockdownRecord {
            return hasRemotePairingRecord ? "Lockdown pairing file imported (UDID present; remote keys ignored for minimuxer)" : "Lockdown pairing file imported (UDID present)"
        }
        if hasRemotePairingRecord {
            return "Remote pairing file imported"
        }
        return "Pairing file imported"
    }

    private static func isValidPairingDictionary(_ dictionary: [String: Any]) -> Bool {
        let keys = Set(dictionary.keys)
        return lockdownPairingKeys.isSubset(of: keys) || remotePairingKeys.isSubset(of: keys)
    }

    private static func isValidPairingText(_ text: String) -> Bool {
        let hasLockdownRecord = lockdownPairingKeys.allSatisfy { text.contains($0) }
        let hasRemotePairingRecord = remotePairingKeys.allSatisfy { text.contains($0) }
        return hasLockdownRecord || hasRemotePairingRecord
    }

    private static let lockdownPairingKeys: Set<String> = [
        "DeviceCertificate",
        "HostCertificate",
        "RootCertificate",
        "SystemBUID",
        "HostID",
        "WiFiMACAddress",
        "EscrowBag",
        "UDID"
    ]

    private static let remotePairingKeys: Set<String> = [
        "PairRecordData",
        "private_key"
    ]

    private static func normalizedPairingData(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw NSError(domain: "FeatherSigningMaterialStore", code: 64, userInfo: [NSLocalizedDescriptionKey: "The pairing file is empty."]) }
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            guard let dictionary = plist as? [String: Any], !dictionary.isEmpty else {
                throw NSError(domain: "FeatherSigningMaterialStore", code: 64, userInfo: [NSLocalizedDescriptionKey: "The pairing file is not a plist dictionary."])
            }
            if !isValidPairingDictionary(dictionary) {
                throw NSError(domain: "FeatherSigningMaterialStore", code: 64, userInfo: [NSLocalizedDescriptionKey: "The pairing file does not include a complete KittyStore pairing record."])
            }
            return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        }
        if let text = String(data: data, encoding: .utf8), isValidPairingText(text) {
            return data
        }
        throw NSError(domain: "FeatherSigningMaterialStore", code: 64, userInfo: [NSLocalizedDescriptionKey: "The pairing file could not be decoded."])
    }

    private static func stageFakefsFile(data: Data, path: String) async -> String? {
        do {
            try await IshFS.createDirectoryIfNeeded(path: (path as NSString).deletingLastPathComponent)
            try await IshFS.writeFile(path: path, data: data)
            return nil
        } catch {
            return "\(path): \(error.localizedDescription)"
        }
    }

    private static func stageFakefsItem(from source: URL, to path: String) async -> String? {
        do {
            if try resourceIsDirectory(source) {
                try await IshFS.createDirectoryIfNeeded(path: path)
                let fileManager = FileManager.default
                guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return "\(path): could not enumerate directory" }
                for case let fileURL as URL in enumerator {
                    let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else { continue }
                    let target = path + "/" + relativePath(fileURL, base: source)
                    try await IshFS.createDirectoryIfNeeded(path: (target as NSString).deletingLastPathComponent)
                    try await IshFS.writeFile(path: target, sourceURL: fileURL)
                }
            } else {
                try await IshFS.createDirectoryIfNeeded(path: (path as NSString).deletingLastPathComponent)
                try await IshFS.writeFile(path: path, sourceURL: source)
            }
            return nil
        } catch {
            return "\(path): \(error.localizedDescription)"
        }
    }

    private static func resourceIsDirectory(_ url: URL) throws -> Bool {
        (try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func resourceIsDirectoryScoped(_ url: URL) throws -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try resourceIsDirectory(url)
    }

    private static func itemSize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        if (try? resourceIsDirectory(url)) == true {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else { return 0 }
            return enumerator.compactMap { item -> Int64? in
                guard let fileURL = item as? URL else { return nil }
                return Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }.reduce(0, +)
        }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private static func sanitizedFileName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        let disallowed = CharacterSet(charactersIn: "/\\:\0")
        let cleaned = source.unicodeScalars.map { disallowed.contains($0) ? "-" : String($0) }.joined()
        let value = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }

    private static func relativePath(_ url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(basePath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func keyValueLines(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in lines(text) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return values
    }
}
