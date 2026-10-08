# iOS persistent diagnostics

Release and Debug save every LLog level, including debug fields, to Documents/Diagnostics. Both iOS variants retain UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace. Launch the updated app, then use Files → Browse → On My iPhone/iPad → Alley Cãt → Diagnostics. The sideload display name is Alley Cat.

Logs cover existing app logging sites, lifecycle, reachability, runtime startup, store update kinds, and archive request/acknowledgement/failure with server/thread IDs. They omit raw payload bodies and sensitive structured fields. This is iOS platform logging; shared session behavior and Android remain unchanged. It does not fix thread-not-found or capture every uninstrumented action/native crash. MetricKit reports appear only when iOS delivers them.

Session logs rotate at 2 MB with 10 retained files. Review exports for remaining IDs, paths and error text before sharing. XCTest covers debug persistence, sensitive fields, prior sessions and rotation; native CI/device verification is required.
