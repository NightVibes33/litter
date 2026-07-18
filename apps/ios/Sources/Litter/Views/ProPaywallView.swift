import SwiftUI

struct ProPaywallView: View {
    let feature: ProFeature
    var onUnlocked: (() -> Void)? = nil

    @State private var store = ProAccessStore.shared

    var body: some View {
        ZStack {
            AlleyBackdrop().ignoresSafeArea()
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
            VStack(spacing: 14) {
                Image("app_icon_current")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(LitterTheme.border.opacity(0.65), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)

                VStack(spacing: 6) {
                    Text(feature.title)
                        .litterFont(.title2, weight: .bold)
                        .foregroundStyle(LitterTheme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(feature.lockedMessage)
                        .litterFont(.subheadline)
                        .foregroundStyle(LitterTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    valuePill("One-time", icon: "sparkles")
                    valuePill(store.displayPrice, icon: "tag.fill")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
            .listRowBackground(LitterTheme.surface.opacity(0.88))
        }
    }

    private var includedSection: some View {
        Section {
            proRow("Terminal", detail: "Run local shell commands in the shared iSH workspace", icon: "terminal")
            proRow("Full File Browser", detail: "Browse, preview, import, export, move, rename, and delete files", icon: "folder")
            proRow("Chat Appearance", detail: "Apply custom chat backgrounds and typing effects", icon: "paintbrush")
            proRow("App Icons", detail: "Switch between the Alley Cãt icon and the original icon", icon: "app.fill")
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
                .listRowBackground(LitterTheme.surface.opacity(0.88))
            } else {
                Button {
                    Task { await store.purchasePro() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(LitterTheme.textOnAccent)
                            .frame(width: 28, height: 28)
                            .background(LitterTheme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock Alley Cãt Pro")
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
                .listRowBackground(LitterTheme.surface.opacity(0.88))

                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Text("Restore Purchases")
                        .litterFont(.subheadline)
                        .foregroundStyle(LitterTheme.accent)
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.purchaseState == .purchasing)
                .listRowBackground(LitterTheme.surface.opacity(0.88))
            }
        } footer: {
            Text("Purchases are handled by Apple. TestFlight purchases use Apple's sandbox and do not charge real money.")
                .foregroundStyle(LitterTheme.textMuted)
        }
    }

    private func valuePill(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .litterFont(.caption, weight: .semibold)
        }
        .foregroundStyle(LitterTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LitterTheme.surfaceLight.opacity(0.55), in: Capsule())
        .overlay {
            Capsule().stroke(LitterTheme.border.opacity(0.45), lineWidth: 1)
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .listRowBackground(LitterTheme.surface.opacity(0.88))
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Text(message)
                .litterFont(.caption)
                .foregroundStyle(LitterTheme.danger)
                .listRowBackground(LitterTheme.surface.opacity(0.88))
        }
    }
}
