# Embedded upstream acceptance

KittyStore now retains SideStore’s normal default-source seeding and host InstalledApp registration. Previous embedded startup removed both and skipped the standard path. My Apps represents this store’s managed database, not all device apps or another SideStore installation’s private database. Existing store-managed rows are retained; records previously deleted cannot be reconstructed from arbitrary device listings without installation/signing metadata.

News uses upstream sources. Endpoint HTTP 403 was observed from the execution workspace; this does not establish the phone’s exact fetch error. Source refresh and news decoding need device diagnostics. No invented news or fallback source is added.

Nyxian uses its bundled CoreCompiler/resources and upstream SDK/bootstrap path; the root CA install has a root-owned retry repair. Verify bootstrap, project build, signing and launch separately. KittyStore also needs physical pairing import, LocalDevVPN transport, account sign-in, IPA installation, refresh and managed-app persistence checks. Source parity alone does not prove these work inside a shared host process. Full audit is incomplete.

## Startup comparison against the pinned standalone sources

| Upstream responsibility | Embedded handling | Acceptance |
| --- | --- | --- |
| SideStore defaults, transformers, database | Runtime prepares these; normal source/host registration restored | Native/device pending |
| SideStore My Apps | Existing managed database and upstream update routine retained | Other app databases are not inherited |
| SideStore news | Source refresh and news decoder retained; default source restored | Phone fetch error still needed; workspace endpoints returned HTTP 403 |
| SideStore foreground/background | Added forwarding for app update, proxy lifecycle and error retention; retry deferred transport | Native/device pending |
| SideStore background refresh | Host fetch callback forwards retained upstream source/news/update and AppManager backgroundRefresh logic; saved settings retained | Native/device pending; iOS controls scheduling |
| SideStore pairing/signing/install/refresh | Existing minimuxer and AltSign entry points retained | Physical-device validation still needed |
| SideStore URL import/backup callbacks | Host forwards install/source/IPA imports, backup and certificate callbacks after storyboard readiness; pairing export requires consent | Native/device pending |
| Nyxian userspace boot | Added missing PEUserspaceManager boot before window/UI creation, retaining current extension setting | Native/device pending |
| Nyxian scene/window presentation | Existing window-server/swizzle/controller startup retained | Physical UI checks still needed |
| Nyxian bootstrap files/SDK/root CA | Same resources/SDK path, atomic root CA retry, root isolated to Documents/Nyxian | Fresh bootstrap/device pending |
| Nyxian failure cleanup | Clears its own bootstrap root only, preserving host documents | Source regression passes |
| Nyxian projects/build/run/signing | Upstream controllers/bridges retained | Device build, export and launch pending |

The new bootstrap root does not delete or migrate old Documents/Projects. Existing files remain accessible in Files. This is a shared host, so isolated upstream app containers must be represented explicitly; blindly reusing standalone Documents cleanup would destroy the host's data. Unchecked routes above are concrete remaining work, not a claim of full parity.

The unsigned host registers its own `kittystore` URL scheme, retaining `litterauth` for account login. It does not claim the separate SideStore/AltStore apps’ schemes. The safe TestFlight transform removes the store registration. Callback URLs containing pairing/certificate credentials are not logged. Remaining standalone responsibilities (including background tasks/intents and all physical signing/refresh paths) still require audit and acceptance; these changes are not proof of complete upstream parity.

Embedded launch now honors upstream’s saved proxy preference and explicit database-recreation flag instead of resetting/ignoring them. Background fetch preserves the pinned refresh-selection, extended-task and completion paths. The host retains ownership of its application badge rather than letting store update counts overwrite chat counts. Source methods are checked against the retained standalone delegate. The separate SideStore widget extension remains excluded and is not claimed supported.

Host self-refresh registration now records the actual original host ID (`ALTBundleIdentifier` when a signing tool provides it), falling back to the running bundle ID. This does not rename another installed app or import another store’s private database. The standard profile inspection, extension registration and self-refresh bundle cache are restored; removed embedded-mode references had remained after the earlier database cleanup. Self-refresh needs a real device/signing test. Its cached host bundle consumes disk space as in upstream; compiler resources remain compressed inside the bundled framework. No fake catalog release or news payload is supplied.

Nyxian now runs its existing signing-setup check after onboarding (and once when reopening an onboarded embedded screen). Its app switcher is hidden in extension-less mode, matching upstream, and its build-time tab-selection guard matches the standalone delegate. The normal launch now sets the upstream extension-loading default while retaining the upstream persisted one-launch recovery override. Full-sideload Settings exposes the same restart-without-extensions function with a shared-host restart warning. The standalone home-screen shortcut is represented by this Settings action; its original home-screen entry is not registered by the host. Native and device signing validation remain outstanding.

Source fetch now checks HTTP success before JSON decoding, so a server rejection is reported with its status rather than an HTML-body decoding error. No endpoint, source schema, credentials, or news contents are replaced; request URLs/query tokens and response bodies are excluded from the diagnostic. The phone’s exact failure remains needed. No legacy-record migration is applied without evidence of a duplicate record; the restored database changes have not yet shipped in a validated installed IPA.

Incoming store callbacks are delivered one at a time after the store is attached and the app is active. An existing dialog postpones delivery; foreground/reattachment resumes it. The queue is bounded before IPA staging. This avoids dropping callback dialogs during cold startup or overlapping link opens; UIKit interaction still needs native/device testing.

The bare RefreshAllIntent compatibility stub is removed. The project now includes the pinned legacy definitions/handlers, INInteraction donation helper and modern App Intents. The host forwards legacy intent requests to retained handlers and declares the embedded AppIntentsPackage for discovery; modern refresh initializes embedded defaults/transport before using the existing AppManager routine. The standalone source keeps its original startup path outside the explicit embedded build condition. Safe TestFlight removes INIntentsSupported and excludes the store discovery package. Native code generation, discovery in Siri/Shortcuts, cancellation/foreground continuation and actual refresh all remain acceptance gates. The separate AltWidget extension and its provisioning/app-group setup are not restored by this change.

### Sideload V8 entitlement request

Unsigned Xcode archives disable code signing and therefore do not encode project entitlements in the app Mach-O. Packaging now adds an ad-hoc executable signature requesting `com.apple.developer.kernel.extended-virtual-addressing`, then reads it back and fails if absent. This supplies the entitlement request read by AltSign; it does not authorize the capability. The final SideStore signature and Apple provisioning profile must retain/grant the entitlement for V8 sandbox reservation. Native packaging and installed-device verification remain required; a repeated tool crash needs its own crash report to confirm FatalOOM. TestFlight signing is unchanged.
