//
//  InfoPlistParser.swift
//  SideSign
//
//  Created by Magesh K on 13/09/26.
//  Copyright © 2026 SideSign. All rights reserved.
//

import Foundation
import CodeSignKit

public struct InfoPlistParser: Sendable {
    public private(set) var rawDictionary: [String: any Sendable]

    public var dictionary: [String: any Sendable] { rawDictionary }

    public init(dictionary: [String: any Sendable]) {
        self.rawDictionary = dictionary
    }

    public init(dictionary: [String: Any]) {
        if let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: any Sendable] {
            self.rawDictionary = plist
        } else {
            self.rawDictionary = [:]
        }
    }

    public init(data: Data) throws {
        guard let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: any Sendable] else {
            throw SignerError.invalidApp(cause: "Invalid PropertyList data format.")
        }
        self.rawDictionary = dict
    }

    public init(plistURL: URL) throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            throw SignerError.missingInfoPlist(path: plistURL.path)
        }
        let data = try Data(contentsOf: plistURL)
        try self.init(data: data)
    }

    public init(bundleURL: URL) throws {
        let plistURL = Self.resolveInfoPlistURL(for: bundleURL)
        try self.init(plistURL: plistURL)
    }

    public static func resolveInfoPlistURL(for fileURL: URL) -> URL {
        let directURL = fileURL.appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }
        let macURL = fileURL.appendingPathComponent("Contents").appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: macURL.path) {
            return macURL
        }
        if let bundle = Bundle(url: fileURL),
           let url = bundle.url(forResource: "Info", withExtension: "plist"),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return directURL
    }

    public var bundleIdentifier: String? {
        (rawDictionary["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (rawDictionary["bundle-identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var appName: String {
        displayName ?? bundleName ?? "Unknown"
    }

    public var displayName: String? {
        rawDictionary["CFBundleDisplayName"] as? String
    }

    public var bundleName: String? {
        rawDictionary["CFBundleName"] as? String
    }

    public var executableName: String? {
        rawDictionary["CFBundleExecutable"] as? String
    }

    public var shortVersionString: String? {
        (rawDictionary["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    public var buildVersion: String? {
        (rawDictionary["CFBundleVersion"] as? String) ?? "1"
    }

    public var displayVersion: String {
        let short = shortVersionString
        let build = buildVersion
        if let short = short, let build = build {
            return "\(short) (\(build))"
        }
        return short ?? build ?? "N/A"
    }

    public var minimumOSVersion: String? {
        rawDictionary["MinimumOSVersion"] as? String
    }

    public var operatingSystemVersion: OperatingSystemVersion {
        let minimumVersionString = minimumOSVersion ?? "1.0"
        let components = minimumVersionString.split(separator: ".")
        return OperatingSystemVersion(
            majorVersion: Int(components.first ?? "1") ?? 1,
            minorVersion: components.count > 1 ? (Int(components[1]) ?? 0) : 0,
            patchVersion: components.count > 2 ? (Int(components[2]) ?? 0) : 0
        )
    }

    public var supportedDeviceTypes: DeviceType {
        func deviceType(from value: Int) -> DeviceType {
            switch value {
            case UIDeviceFamilyCodes.iPhone:     return .iPhone
            case UIDeviceFamilyCodes.iPad:       return .iPad
            case UIDeviceFamilyCodes.appleTV:    return .appleTV
            case UIDeviceFamilyCodes.appleWatch: return .appleWatch
            case UIDeviceFamilyCodes.mac:        return .mac
            case UIDeviceFamilyCodes.visionPro:  return .visionPro
            default:                             return .iPhone
            }
        }

        if let number = rawDictionary["UIDeviceFamily"] as? NSNumber {
            return deviceType(from: number.intValue)
        } else if let array = rawDictionary["UIDeviceFamily"] as? [NSNumber] {
            var supportedTypes: DeviceType = []
            for value in array {
                supportedTypes.insert(deviceType(from: value.intValue))
            }
            return supportedTypes
        } else {
            return .iPhone
        }
    }

    public var primaryIconName: String? {
        if let icons = rawDictionary["CFBundleIcons"] as? [String: any Sendable],
           let primary = icons["CFBundlePrimaryIcon"] {
            if let iconStr = primary as? String {
                return iconStr
            } else if let dict = primary as? [String: any Sendable] {
                let files = dict["CFBundleIconFiles"] ?? rawDictionary["CFBundleIconFiles"]
                if let files = files as? [String] {
                    return files.last
                }
            }
        }
        return rawDictionary["CFBundleIconFile"] as? String
    }

    public var isFileSharingEnabled: Bool {
        rawDictionary["UIFileSharingEnabled"] as? Bool ?? false
    }

    public var supportsOpeningDocumentsInPlace: Bool {
        rawDictionary["LSSupportsOpeningDocumentsInPlace"] as? Bool ?? false
    }

    public var backgroundModes: [String] {
        rawDictionary["UIBackgroundModes"] as? [String] ?? []
    }

    public var customURLSchemes: [String] {
        guard let urlTypes = rawDictionary["CFBundleURLTypes"] as? [[String: any Sendable]] else { return [] }
        return urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
    }

    public var queriedURLSchemes: [String] {
        rawDictionary["LSApplicationQueriesSchemes"] as? [String] ?? []
    }

    public var privacyPermissions: [String: String] {
        var dict = [String: String]()
        for (key, val) in rawDictionary where key.hasPrefix("NS") && key.hasSuffix("UsageDescription") {
            if let str = val as? String { dict[key] = str }
        }
        return dict
    }

    public mutating func set(value: (any Sendable)?, for key: String) {
        rawDictionary[key] = value
    }

    public mutating func merge(_ dictionary: [String: any Sendable], deep: Bool = true) {
        rawDictionary = deep
            ? Self.deepMerge(target: rawDictionary, source: dictionary)
            : Self.shallowMerge(target: rawDictionary, source: dictionary)
    }

    public static func deepMerge(target: [String: any Sendable], source: [String: any Sendable]) -> [String: any Sendable] {
        var result = target
        for (key, sourceValue) in source {
            if let targetDict = result[key] as? [String: any Sendable],
               let sourceDict = sourceValue as? [String: any Sendable] {
                result[key] = deepMerge(target: targetDict, source: sourceDict)
            } else {
                result[key] = sourceValue
            }
        }
        return result
    }

    public static func shallowMerge(target: [String: any Sendable], source: [String: any Sendable]) -> [String: any Sendable] {
        var result = target
        for (key, value) in source {
            result[key] = value
        }
        return result
    }

    public func toXMLData() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: rawDictionary, format: .xml, options: 0)
    }

    public func toJSONData() throws -> Data {
        try JSONSerialization.data(withJSONObject: rawDictionary, options: [.prettyPrinted, .sortedKeys])
    }

    public func write(to url: URL) throws {
        let data = try toXMLData()
        try data.write(to: url, options: .atomic)
    }

    public static func sanitizeBundleID(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        var sanitized = raw.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        while sanitized.contains("..") {
            sanitized = sanitized.replacingOccurrences(of: "..", with: ".")
        }
        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }
}
