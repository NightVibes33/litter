#!/usr/bin/env python3
"""Patch emexDE sources that depend on the generated Swift ObjC header.

Fresh GitHub iOS runners can compile Objective-C files before emexDE-Swift.h
is available to those files. This keeps upstream sources in the repo and rewrites
only CI checkout copies to use local Objective-C shims for the small bridge types
those files reference.
"""
from pathlib import Path

changed = []
for source in Path("ThirdParty/EmexDE/Source").rglob("*"):
    if source.suffix not in {".h", ".m", ".mm", ".cpp", ".hpp"}:
        continue
    text = source.read_text(errors="ignore")
    normalized = text.replace("#import <emexDE-Swift.h>", '#import "emexDE-Swift.h"')
    if normalized != text:
        source.write_text(normalized)
        changed.append(source)

terminal_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/UIInit/Terminal.swift")
bridge_text = terminal_bridge.read_text()
bridge_replacements = {
    "@objc protocol TerminalViewDelegateObjC: AnyObject": "@objc(TerminalViewDelegateObjC) public protocol TerminalViewDelegateObjC: AnyObject",
    "@objc class TerminalViewObjC: TerminalView": "@objc(TerminalViewObjC) public class TerminalViewObjC: TerminalView",
    "@objc var ttyHandle: FileHandle?": "@objc public var ttyHandle: FileHandle?",
    "required init?(coder: NSCoder)": "public required init?(coder: NSCoder)",
    "override func willMove(toWindow newWindow: UIWindow?)": "public override func willMove(toWindow newWindow: UIWindow?)",
    "@objc func handleThemeChange(_ notification: Notification?)": "@objc public func handleThemeChange(_ notification: Notification?)",
    "override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)": "public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?)",
}
for before, after in bridge_replacements.items():
    if before not in bridge_text and after not in bridge_text:
        raise SystemExit(f"Missing expected emexDE terminal bridge declaration: {before}")
    bridge_text = bridge_text.replace(before, after)
terminal_bridge.write_text(bridge_text)

terminal_session = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/WindowServer/Session/NXWindowSessionTerminal.m")
terminal_session_text = terminal_session.read_text()
terminal_session_shim = "\n".join([
    "#import <UIKit/UIKit.h>",
    "@class TerminalView;",
    "@protocol TerminalViewDelegateObjC <NSObject>",
    "@end",
    "@interface TerminalViewObjC : UIView",
    "@property (nonatomic, weak, nullable) id<TerminalViewDelegateObjC> objcDelegate;",
    "@property (nonatomic, strong, nullable) NSFileHandle *ttyHandle;",
    "- (nonnull instancetype)initWithFrame:(CGRect)frame masterFD:(int32_t)masterFD;",
    "@end",
])
if '#import "emexDE-Swift.h"' not in terminal_session_text and terminal_session_shim not in terminal_session_text:
    raise SystemExit("Missing expected emexDE terminal session Swift import")
terminal_session_text = terminal_session_text.replace('#import "emexDE-Swift.h"', terminal_session_shim)
terminal_session.write_text(terminal_session_text)

os_version_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/FileList/iOSVersionPickerView.swift")
os_version_text = os_version_bridge.read_text()
os_version_replacements = {
    "@objc class NXOSVersion: NSObject, Comparable": "@objc(NXOSVersion) public class NXOSVersion: NSObject, Comparable",
    "@objc let versionString: String": "@objc public let versionString: String",
    "@objc let versionNumeric: Double": "@objc public let versionNumeric: Double",
    "@objc private(set) var pickerVersionString: String": "@objc public private(set) var pickerVersionString: String",
    "@objc static let hostVersion: NXOSVersion": "@objc public static let hostVersion: NXOSVersion",
    "@objc static var minimumBuildVersion: NXOSVersion": "@objc public static var minimumBuildVersion: NXOSVersion",
    "@objc static var maximumBuildVersion: NXOSVersion": "@objc public static var maximumBuildVersion: NXOSVersion",
    "@objc static var iPadOSMinimumValidityVersion: NXOSVersion": "@objc public static var iPadOSMinimumValidityVersion: NXOSVersion",
    "@objc init?(versionString inputString: String?)": "@objc public init?(versionString inputString: String?)",
    "@objc override convenience init()": "@objc public override convenience init()",
    "static func == (lhs: NXOSVersion, rhs: NXOSVersion) -> Bool": "public static func == (lhs: NXOSVersion, rhs: NXOSVersion) -> Bool",
    "static func < (lhs: NXOSVersion, rhs: NXOSVersion) -> Bool": "public static func < (lhs: NXOSVersion, rhs: NXOSVersion) -> Bool",
    "@objc override var description: String": "@objc public override var description: String",
    "@objc override func isEqual(_ object: Any?) -> Bool": "@objc public override func isEqual(_ object: Any?) -> Bool",
    "@objc override var hash: Int": "@objc public override var hash: Int",
}
for before, after in os_version_replacements.items():
    if before not in os_version_text and after not in os_version_text:
        raise SystemExit(f"Missing expected emexDE NXOSVersion declaration: {before}")
    os_version_text = os_version_text.replace(before, after)
os_version_bridge.write_text(os_version_text)

notification_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/Project/Project+NotificationServer.swift")
notification_text = notification_bridge.read_text()
notification_replacements = {
    "@objc class NotificationServer: NSObject": "@objc(NotificationServer) public class NotificationServer: NSObject",
    "@objc enum NotifLevel: Int": "@objc public enum NotifLevel: Int",
    "@objc static func NotifyUser(": "@objc public static func NotifyUser(",
}
for before, after in notification_replacements.items():
    if before not in notification_text and after not in notification_text:
        raise SystemExit(f"Missing expected emexDE notification bridge declaration: {before}")
    notification_text = notification_text.replace(before, after)
notification_bridge.write_text(notification_text)

application_management_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/Settings/ApplicationManagement.swift")
application_management_text = application_management_bridge.read_text()
application_management_before = "class ApplicationManagementViewController: UIThemedTableViewController, UITextFieldDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate"
application_management_after = "@objc(ApplicationManagementViewController) class ApplicationManagementViewController: UIThemedTableViewController, UITextFieldDelegate, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate"
if application_management_before not in application_management_text and application_management_after not in application_management_text:
    raise SystemExit("Missing expected emexDE ApplicationManagementViewController declaration")
application_management_bridge.write_text(application_management_text.replace(application_management_before, application_management_after))

def replace_generated_swift_import(source_path, shim, label):
    source = Path(source_path)
    source_text = source.read_text()
    marker = '#import "emexDE-Swift.h"'
    if marker not in source_text:
        if shim and shim in source_text:
            return
        if not shim:
            return
        raise SystemExit(f"Missing expected emexDE Swift import for {label}")
    source.write_text(source_text.replace(marker, shim))

notification_objc_shim = "\n".join([
    "#import <Foundation/Foundation.h>",
    "typedef NS_ENUM(NSInteger, NotifLevel) {",
    "    NotifLevelNote = 0,",
    "    NotifLevelWarning = 1,",
    "    NotifLevelError = 2,",
    "};",
    "@interface NotificationServer : NSObject",
    "+ (void)NotifyUserWithLevel:(NotifLevel)level notification:(NSString *)notification delay:(double)delay;",
    "@end",
])
nxos_version_objc_shim = "\n".join([
    "#import <Foundation/Foundation.h>",
    "#import <NXBootstrap.h>",
    "@interface NXOSVersion : NSObject",
    "+ (NXOSVersion *)hostVersion;",
    "+ (NXOSVersion *)maximumBuildVersion;",
    "@property (nonatomic, readonly, copy) NSString *versionString;",
    "@property (nonatomic, readonly, copy) NSString *pickerVersionString;",
    "@end",
])
application_management_objc_shim = "\n".join([
    "#import <Foundation/Foundation.h>",
    "@class LDEApplicationObject;",
    "@interface ApplicationManagementViewController : NSObject",
    "+ (instancetype)shared;",
    "- (void)applicationWasInstalled:(LDEApplicationObject *)app;",
    "- (void)applicationWithBundleIdentifierWasUninstalled:(NSString *)bundleIdentifier;",
    "@end",
])
replace_generated_swift_import(
    "ThirdParty/EmexDE/Source/Nyxian/NXBootstrap.m",
    notification_objc_shim,
    "NXBootstrap notification bridge",
)
replace_generated_swift_import(
    "ThirdParty/EmexDE/Source/Nyxian/LindChain/ProcEnvironment/Process/PEProcessManager.m",
    notification_objc_shim,
    "PEProcessManager notification bridge",
)
replace_generated_swift_import(
    "ThirdParty/EmexDE/Source/Nyxian/LindChain/Project/NXTarget.m",
    nxos_version_objc_shim,
    "NXTarget OS version bridge",
)
replace_generated_swift_import(
    "ThirdParty/EmexDE/Source/Nyxian/LindChain/Project/NXProject.m",
    nxos_version_objc_shim,
    "NXProject OS version bridge",
)
replace_generated_swift_import(
    "ThirdParty/EmexDE/Source/LiveProcess/LindChain/Services/applicationmgmtd/LDEApplicationWorkspace.m",
    application_management_objc_shim,
    "LDEApplicationWorkspace application-management bridge",
)
replace_generated_swift_import(
    "ThirdParty/EmexDE/Source/Nyxian/LindChain/JBSupport/Shell.m",
    "",
    "Shell unused Swift import",
)

cc_driver = Path("ThirdParty/EmexDE/Source/CoreCompiler/Tools/CCDriver.cpp")
cc_driver_text = cc_driver.read_text()
cc_driver_before = '        case CCDriverTypeSwift:\n        {\n            if(!driver->swiftCompilation)\n            {\n                return nullptr;\n            }\n            const auto &Args = driver->swiftCompilation->getArgs();\n            if(const llvm::opt::Arg *A = Args.getLastArg(swift::options::OPT_sdk))\n            {\n                cxxstr = A->getValue();\n            }\n            break;\n        }\n'
cc_driver_after = '        case CCDriverTypeSwift:\n        {\n            for(size_t i = 0; i + 1 < driver->argStorage.size(); ++i)\n            {\n                if(driver->argStorage[i] == "-sdk")\n                {\n                    cxxstr = driver->argStorage[i + 1];\n                    break;\n                }\n            }\n            break;\n        }\n'
if cc_driver_before not in cc_driver_text and cc_driver_after not in cc_driver_text:
    raise SystemExit("Missing expected CoreCompiler Swift SDK lookup block")
cc_driver.write_text(cc_driver_text.replace(cc_driver_before, cc_driver_after))

def ensure_liveprocess_info_plist_metadata():
    plist_path = Path("ThirdParty/EmexDE/Source/LiveProcess/Info.plist")
    plist_text = plist_path.read_text()
    if "<key>CFBundleIdentifier</key>" in plist_text:
        return
    plist_metadata = "\n".join([
        "\t<key>CFBundleDevelopmentRegion</key>",
        "\t<string>$(DEVELOPMENT_LANGUAGE)</string>",
        "\t<key>CFBundleDisplayName</key>",
        "\t<string>LiveProcess</string>",
        "\t<key>CFBundleExecutable</key>",
        "\t<string>$(EXECUTABLE_NAME)</string>",
        "\t<key>CFBundleIdentifier</key>",
        "\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>",
        "\t<key>CFBundleInfoDictionaryVersion</key>",
        "\t<string>6.0</string>",
        "\t<key>CFBundleName</key>",
        "\t<string>LiveProcess</string>",
        "\t<key>CFBundlePackageType</key>",
        "\t<string>XPC!</string>",
        "\t<key>CFBundleShortVersionString</key>",
        "\t<string>$(MARKETING_VERSION)</string>",
        "\t<key>CFBundleVersion</key>",
        "\t<string>$(CURRENT_PROJECT_VERSION)</string>",
        "",
    ])
    if "<dict>\n" not in plist_text:
        raise SystemExit("Missing LiveProcess Info.plist root dict")
    plist_path.write_text(plist_text.replace("<dict>\n", "<dict>\n" + plist_metadata, 1))

ensure_liveprocess_info_plist_metadata()

print(f"Normalized {len(changed)} emexDE generated Swift imports.")
for source in changed:
    print(source)
print("Exposed emexDE Swift bridge declarations for generated ObjC headers.")
