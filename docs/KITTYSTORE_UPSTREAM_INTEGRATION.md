# Embedded upstream acceptance

KittyStore now retains SideStore’s normal default-source seeding and host InstalledApp registration. Previous embedded startup removed both and skipped the standard path. My Apps represents this store’s managed database, not all device apps or another SideStore installation’s private database. Existing store-managed rows are retained; records previously deleted cannot be reconstructed from arbitrary device listings without installation/signing metadata.

News uses upstream sources. Endpoint HTTP 403 was observed from the execution workspace; this does not establish the phone’s exact fetch error. Source refresh and news decoding need device diagnostics. No invented news or fallback source is added.

Nyxian uses its bundled CoreCompiler/resources and upstream SDK/bootstrap path; the root CA install has a root-owned retry repair. Verify bootstrap, project build, signing and launch separately. KittyStore also needs physical pairing import, LocalDevVPN transport, account sign-in, IPA installation, refresh and managed-app persistence checks. Source parity alone does not prove these work inside a shared host process. Full audit is incomplete.
