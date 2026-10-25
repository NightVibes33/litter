#!/usr/bin/env python3
"""Patch emexDE sources that depend on the generated Swift ObjC header.

The emexDE framework must expose the real Swift-generated Nyxian-Swift.h.
Never replace upstream Objective-C imports with locally invented declarations,
or bypass its genuine NXApplicationState class.
"""
from pathlib import Path

changed = []

# The embedded host must keep iOS LaunchServices intact. Replacing its app
# proxies with virtual Nyxian apps also affects system document-picker setup.
launch_services = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/ProcEnvironment/Shims/LSApplicationWorkspace.m")
launch_services_text = launch_services.read_text()
load_before = "+ (void)load\n{\n    [super load];"
load_after = load_before + "\n#if LITTER_EMBEDDED_NYXIAN\n    return;\n#endif"
if load_after not in launch_services_text:
    if load_before not in launch_services_text:
        raise SystemExit("Missing expected Nyxian LaunchServices hook installer")
    launch_services.write_text(launch_services_text.replace(load_before, load_after, 1))

for source in Path("ThirdParty/EmexDE/Source").rglob("*"):
    if source.suffix not in {".h", ".m", ".mm", ".cpp", ".hpp"}:
        continue
    text = source.read_text(errors="ignore")
    normalized = (text.replace("#import <Nyxian-Swift.h>", '#import <emexDE/Nyxian-Swift.h>')
                      .replace("#import <emexDE-Swift.h>", '#import <emexDE/Nyxian-Swift.h>')
                      .replace('#import "Nyxian-Swift.h"', '#import <emexDE/Nyxian-Swift.h>'))
    if normalized != text:
        source.write_text(normalized)
        changed.append(source)

# Expose the actual upstream class under a stable ObjC name.
theme_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/CodeEditor/CodeEditor+Theme.swift")
theme_text = theme_bridge.read_text()
theme_before = "@objc class LDETheme: NSObject, Theme {"
theme_after = "@objc(LDETheme) class LDETheme: NSObject, Theme {"
if theme_before not in theme_text and theme_after not in theme_text:
    raise SystemExit("Missing expected emexDE LDETheme declaration")
theme_bridge.write_text(theme_text.replace(theme_before, theme_after))

terminal_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/UIInit/Terminal.swift")
bridge_text = terminal_bridge.read_text()
bridge_replacements = {
    "@objc protocol TerminalViewDelegateObjC: AnyObject": "@objc(TerminalViewDelegateObjC) public protocol TerminalViewDelegateObjC: AnyObject",
    "@objc class TerminalViewObjC: TerminalView": "@objc(TerminalViewObjC) public class TerminalViewObjC: TerminalView",
    "@objc var ttyHandle: FileHandle?": "@objc public var ttyHandle: FileHandle?",
    "required init?(coder: NSCoder)": "public required init?(coder: NSCoder)",
    "override func willMove(toWindow newWindow: UIWindow?)": "public override func willMove(toWindow newWindow: UIWindow?)",
    "@objc func handleThemeChange(_ notification: Notification?)": "@objc public func handleThemeChange(_ notification: Notification?)",
}
for before, after in bridge_replacements.items():
    if before not in bridge_text and after not in bridge_text:
        raise SystemExit(f"Missing expected emexDE terminal bridge declaration: {before}")
    bridge_text = bridge_text.replace(before, after)
terminal_bridge.write_text(bridge_text)

# NXWindowSessionTerminal uses the real generated Swift interface.

os_version_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/FileList/iOSVersionPickerView.swift")
os_version_text = os_version_bridge.read_text()
os_version_replacements = {
    "@objc class NXOSVersion: NSObject": "@objc(NXOSVersion) public class NXOSVersion: NSObject",
    "@objc static var NXOSVersionSupportedBuildVersionsRaw: [MDKOSVersion]": "@objc public static var NXOSVersionSupportedBuildVersionsRaw: [MDKOSVersion]",
    "@objc static var NXOSVersionSupportedBuildVersions: [String]": "@objc public static var NXOSVersionSupportedBuildVersions: [String]",
}
for before, after in os_version_replacements.items():
    if before not in os_version_text and after not in os_version_text:
        raise SystemExit(f"Missing expected emexDE NXOSVersion declaration: {before}")
    os_version_text = os_version_text.replace(before, after)
os_version_bridge.write_text(os_version_text)

notification_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEFoundation/Project+NotificationServer.swift")
# Older Nyxian revisions declared NotificationServer in a Swift file.
# Current upstream provides NXAlertDiagnosticPresenter in Objective-C instead.
# Keep compatibility with both source graphs; do not invent a missing file.
if notification_bridge.is_file():
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
elif not Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h").is_file():
    raise SystemExit("Missing both legacy NotificationServer and upstream NXAlertDiagnosticPresenter")

application_management_bridge = Path("ThirdParty/EmexDE/Source/Nyxian/UI/Settings/ApplicationManagement.swift")
application_management_text = application_management_bridge.read_text()
# NXUITableViewController replaced UIThemedTableViewController upstream.
# Expose the ObjC symbol without pinning its superclass to the old version.
application_management_before = "class ApplicationManagementViewController: "
application_management_after = "@objc(ApplicationManagementViewController) class ApplicationManagementViewController: "
if application_management_after not in application_management_text:
    if application_management_before not in application_management_text:
        raise SystemExit("Missing expected emexDE ApplicationManagementViewController declaration")
    application_management_text = application_management_text.replace(application_management_before, application_management_after, 1)
application_management_bridge.write_text(application_management_text)

# Keep every Swift/Objective-C consumer connected to the actual upstream types.
# No hand-authored shims and no rewrites of real Swift feature implementations.

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

# A partially completed bootstrap can leave the root CA installed before the
# version marker advances. Replace from the same upstream download atomically.
bootstrap = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/IDEFoundation/NXBootstrap.m")
bootstrap_text = bootstrap.read_text()
# NXBootstrap continues to call upstream NXApplicationState.extensionLessMode
# using the generated Swift-to-ObjC header, not a stand-in declaration.

# Standalone Nyxian owns all of Documents; embedded Nyxian must own only a
# child directory because upstream failure recovery clears rootURL entirely.
old_root = 'stringByAppendingPathComponent:@"Documents"]];'
new_root = 'stringByAppendingPathComponent:@"Documents/Nyxian"]];'
if old_root in bootstrap_text:
    bootstrap_text = bootstrap_text.replace(old_root, new_root, 1)
elif new_root not in bootstrap_text:
    raise SystemExit("Missing expected NXBootstrap Documents root")

old_rootca = 'if(![[NSFileManager defaultManager] moveItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"org.emexlabs.rootca.v1.pub.nxt2c"] toPath:[[self.rootURL URLByAppendingPathComponent:@"RootCAs/org.emexlabs.rootca.v1.pub.nxt2c"] path] error:nil])'
new_rootca = 'NSData *rootCAData = [NSData dataWithContentsOfFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"org.emexlabs.rootca.v1.pub.nxt2c"] options:0 error:&error];\n                if(!rootCAData || ![rootCAData writeToURL:[self.rootURL URLByAppendingPathComponent:@"RootCAs/org.emexlabs.rootca.v1.pub.nxt2c"] options:NSDataWritingAtomic error:&error])'
if old_rootca in bootstrap_text:
    bootstrap_text = bootstrap_text.replace(old_rootca, new_rootca, 1)
    bootstrap_text = bootstrap_text.replace('error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"failed to move emexlabs public rootca key" }];', 'if(!error) error = [NSError errorWithDomain:@"" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"failed to install emexlabs public rootca key" }];', 1)
    bootstrap.write_text(bootstrap_text)
elif new_rootca not in bootstrap_text:
    raise SystemExit("Missing expected NXBootstrap root CA installation")
bootstrap.write_text(bootstrap_text)

print(f"Normalized {len(changed)} emexDE generated Swift imports.")
for source in changed:
    print(source)
print("Preserved upstream generated Swift-to-Objective-C interface; no fake declarations.")

# Target identity must not depend on whether Xcode has emitted its Swift header.
from nyxian_workspace_host_patch import patch_workspace_host_selector

# The shared LDEApplicationWorkspace.m is compiled twice: once into the
# emexDE host framework and again into the LiveProcess extension. The upstream
# header-presence test is not a reliable discriminator when the embedded
# framework's Swift-generated header has not yet been emitted. Select the real
# host path from the HOST_ENV build flag instead; the extension keeps the
# upstream LiveShim syscall path. Never silently skip a missing submodule file.
workspace = Path("ThirdParty/EmexDE/Source/LiveProcess/LindChain/Services/bootstrapd/LDEApplicationWorkspace.m")
if not workspace.is_file():
    raise SystemExit(f"Missing pinned Nyxian workspace source: {workspace}")
original_workspace = workspace.read_text(encoding="utf-8")
try:
    normalized_workspace = patch_workspace_host_selector(original_workspace)
except ValueError as error:
    raise SystemExit(f"Unsafe Nyxian workspace host selection: {error}") from error
if normalized_workspace != original_workspace:
    workspace.write_text(normalized_workspace, encoding="utf-8")
print(f"Nyxian shared workspace host selection verified: {workspace}")

# Xcode places the generated Swift compatibility header inside the embedded
# emexDE.framework/Headers directory. A quoted header import searches the
# source directory, not the framework's generated public headers. Use a
# framework-qualified import for the remaining Nyxian Objective-C consumers;
# no CI-only shims are used.
framework_import = '#import <emexDE/Nyxian-Swift.h>'
local_import = '#import "Nyxian-Swift.h"'
framework_imports = []
for source in Path("ThirdParty/EmexDE/Source/Nyxian").rglob("*"):
    if source.suffix not in {".h", ".m", ".mm"}:
        continue
    text = source.read_text(errors="ignore")
    if local_import in text:
        source.write_text(text.replace(local_import, framework_import))
        framework_imports.append(str(source))
print(f"Repointed {len(framework_imports)} embedded Nyxian Objective-C Swift header imports to emexDE.framework.")
