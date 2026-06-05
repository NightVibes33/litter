import SwiftUI

struct ProPaywallView: View {
    let feature: ProFeature
    var onUnlocked: (() -> Void)? = nil

    @State private var store = ProAccessStore.shared

    var body: some View {
        ZStack {
            LitterTheme.backgroundGradient.ignoresSafeArea()
            Form {
                heroSection
                includedSection
                purchaseSection
                if case .failed(let message) = store.purchaseState {
                    errorSection(message)
                }
            }
            .scrollContentBackground(.hidden)

            if store.purchaseState == .purchasing {
                Color.black.opacity(0.34).ignoresSafeArea()
                ProgressView()
                    .tint(LitterTheme.accent)
                    .scaleEffect(1.2)
            }
        }
        .navigationTitle("Alley Cãt Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadProducts() }
        .onChange(of: store.hasProAccess) { _, unlocked in
            if unlocked { onUnlocked?() }
        }
    }

    private var heroSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: feature.iconName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LitterTheme.accent)
                    .frame(width: 72, height: 72)
                    .modifier(GlassCircleModifier())
                Text(feature.title)
                    .litterFont(.title2, weight: .bold)
                    .foregroundStyle(LitterTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(feature.lockedMessage)
                    .litterFont(.subheadline)
                    .foregroundStyle(LitterTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(LitterTheme.surface.opacity(0.6))
        }
    }

    private var includedSection: some View {
        Section {
            proRow("Terminal", detail: "Run local shell commands in the shared iSH workspace", icon: "terminal")
            proRow("Full File Browser", detail: "Browse, preview, import, export, move, rename, and delete files", icon: "folder")
            proRow("Advanced Tools", detail: "Use local diagnostics and power-user filesystem actions", icon: "wrench.and.screwdriver")
        } header: {
            Text("Included")
                .foregroundStyle(LitterTheme.textSecondary)
        }
    }

    private var purchaseSection: some View {
        Section {
            if store.hasProAccess {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(LitterTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pro Unlocked")
                            .litterFont(.subheadline, weight: .semibold)
                            .foregroundStyle(LitterTheme.textPrimary)
                        Text("This Apple ID already owns Alley Cãt Pro.")
                            .litterFont(.caption)
                            .foregroundStyle(LitterTheme.textSecondary)
                    }
                }
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            } else {
                Button {
                    Task { await store.purchasePro() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock Pro")
                                .litterFont(.subheadline, weight: .semibold)
                                .foregroundStyle(LitterTheme.textPrimary)
                            Text("One-time purchase")
                                .litterFont(.caption)
                                .foregroundStyle(LitterTheme.textSecondary)
                        }
                        Spacer()
                        Text(store.displayPrice)
                            .litterFont(.subheadline, weight: .bold)
                            .foregroundStyle(LitterTheme.accent)
                    }
                }
                .disabled(store.purchaseState == .purchasing || store.purchaseState == .loading)
                .listRowBackground(LitterTheme.surface.opacity(0.6))

                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Text("Restore Purchases")
                        .litterFont(.subheadline)
                        .foregroundStyle(LitterTheme.accent)
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.purchaseState == .purchasing)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
            }
        } footer: {
            Text("Purchases are handled by Apple. TestFlight purchases use Apple's sandbox and do not charge real money.")
                .foregroundStyle(LitterTheme.textMuted)
        }
    }

    private func proRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(LitterTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .litterFont(.subheadline, weight: .semibold)
                    .foregroundStyle(LitterTheme.textPrimary)
                Text(detail)
                    .litterFont(.caption)
                    .foregroundStyle(LitterTheme.textSecondary)
            }
        }
        .listRowBackground(LitterTheme.surface.opacity(0.6))
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Text(message)
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.danger)
                .listRowBackground(LitterTheme.surface.opacity(0.6))
        }
    }
}
