import SwiftUI

/// Bridge alias: Rust exposes agent identity as an opaque `String` (the
/// lowercase id alleycat advertises). The legacy `AgentRuntimeKind`
/// name is kept as a type alias so call sites compile; ALL agent
/// metadata — label, icon, BETA badge, sort order, capability flags —
/// comes from `AgentMetadataStore` keyed by id. There is no hardcoded
/// catalog of agent names in litter, so adding a new agent only
/// requires an entry in the alleycat manifest.
typealias AgentRuntimeKind = String

/// Lookup hook into the Rust-owned `AgentMetadataStore`. Wired up at
/// app launch in `LitterApp` so any view can resolve an `AgentId` to
/// its metadata. Returns `nil` before the first probe response.
enum AgentRuntimeMetadataProvider {
    static var lookup: ((String) -> AppAgentMetadata?)?
    static var all: (() -> [AppAgentMetadata])?
}

extension AgentRuntimeKind {
    static let claude: AgentRuntimeKind = "claude"
    static let codex: AgentRuntimeKind = "codex"
    static let devin: AgentRuntimeKind = "devin"
    static let droid: AgentRuntimeKind = "droid"
    static let opencode: AgentRuntimeKind = "opencode"

    /// Presentation order surfaced by `AgentMetadataStore` (sorted by
    /// each agent's `presentation.sort_order` from the alleycat
    /// manifest). Empty when no probe has populated the cache yet —
    /// callers should treat that as "no agents available."
    static var presentationOrder: [AgentRuntimeKind] {
        AgentRuntimeMetadataProvider.all?().map(\.name) ?? []
    }

    var metadata: AppAgentMetadata? {
        AgentRuntimeMetadataProvider.lookup?(self)
    }

    /// Short label used in lists. Prefers metadata `display_name`;
    /// falls back to a titlecased id so the UI never shows a blank
    /// label during the brief window between server connect and probe
    /// completion.
    var displayLabel: String {
        if let meta = metadata, !meta.displayName.isEmpty {
            return meta.displayName
        }
        return titlecased
    }

    /// Header / title rendering. Prefers metadata `presentation.title`
    /// (e.g. "Factory Droid") over the short label.
    var titleDisplayLabel: String {
        if let title = metadata?.presentation?.title, !title.isEmpty {
            return title
        }
        return displayLabel
    }

    /// Sort index. Prefers metadata `sort_order`; otherwise drops to
    /// the end, tie-broken by name.
    var presentationSortIndex: Int {
        if let order = metadata?.presentation?.sortOrder {
            return Int(order)
        }
        return Int.max
    }

    /// BETA badge driven entirely by `presentation.is_beta` from
    /// alleycat. Unknown ids (no metadata cached yet) are treated as
    /// beta by default — agents only lose the badge when the manifest
    /// says so.
    var isBeta: Bool {
        metadata?.presentation?.isBeta ?? true
    }

    /// Asset catalog name for this agent's bundled icon, by convention
    /// `agent_<id>`. Returns `nil` when no matching `UIImage(named:)`
    /// is bundled — callers fall back to a monogram chip via
    /// `AgentIconView`. Litter ships icons for the agents it knows
    /// about (codex, claude, etc.) and renders a monogram for anything
    /// new that alleycat advertises.
    var bundledAssetName: String? {
        let candidate = "agent_\(self)"
        return UIImage(named: candidate) != nil ? candidate : nil
    }

    /// Picker / add-server callers check whether an agent should show
    /// a BETA badge before its metadata has been promoted into the
    /// store. With no enum to consult, defer entirely to the cached
    /// metadata; unknown agents are beta by default.
    static func isBetaAgentName(_ name: String, displayName _: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return AgentRuntimeMetadataProvider.lookup?(key)?.presentation?.isBeta ?? true
    }

    private var titlecased: String {
        guard !isEmpty else { return "Agent" }
        return prefix(1).uppercased() + dropFirst()
    }
}

/// Renders an agent's icon from the local asset catalog (`agent_<id>`)
/// when one is bundled, otherwise falls back to a monogram letter chip.
/// Use this everywhere instead of `Image(kind.assetName)` — it keeps
/// new alleycat-advertised agents renderable without shipping a litter
/// release first.
struct AgentIconView: View {
    let kind: AgentRuntimeKind
    var size: CGFloat = 24

    var body: some View {
        if let assetName = kind.bundledAssetName {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            AgentMonogramView(kind: kind, size: size)
        }
    }
}

/// Letter-based fallback when no icon is cached. Renders the first
/// character of the agent id in the accent color over a dark chip —
/// good enough for cold-start before the first probe completes.
struct AgentMonogramView: View {
    let kind: AgentRuntimeKind
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .stroke(LitterTheme.textPrimary.opacity(0.25), lineWidth: 0.5)
                )
            Text(monogramLetter)
                .font(.system(size: size * 0.6, weight: .semibold, design: .monospaced))
                .foregroundColor(LitterTheme.accent)
        }
        .frame(width: size, height: size)
    }

    private var monogramLetter: String {
        kind.first.map { String($0).uppercased() } ?? "?"
    }
}

struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .litterFont(.caption2)
            .foregroundColor(LitterTheme.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(LitterTheme.accent.opacity(0.6), lineWidth: 0.5)
            )
    }
}
