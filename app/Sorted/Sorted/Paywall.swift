import SwiftUI
import StoreKit

// StoreKit 2 engine + paywall. One non-consumable: lifetime unlock.
@MainActor
final class Entitlements: ObservableObject {
    static let productID = "com.olivervirt.dacapo.unlock"

    // Offline-grace cache: set true on any verified entitlement; never auto-false.
    @AppStorage("dacapo.unlocked") var unlocked = false
    @Published var product: Product?
    @Published var purchasing = false
    @Published var loadFailed = false
    private var updatesTask: Task<Void, Never>?

    func start() async {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let t) = update, t.productID == Self.productID {
                    await t.finish()
                    if t.revocationDate == nil { self.unlocked = true }
                }
            }
        }
        await checkEntitlement()
        await loadProduct()
    }

    func checkEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Self.productID, t.revocationDate == nil {
                unlocked = true
            }
        }
    }

    func loadProduct() async {
        loadFailed = false
        do { product = try await Product.products(for: [Self.productID]).first }
        catch { loadFailed = true }
        if product == nil { loadFailed = true }
    }

    func purchase() async {
        guard let product, !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    unlocked = true
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch { /* transient; user can retry */ }
    }

    func restore() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }
}

struct PaywallView: View {
    @EnvironmentObject var ent: Entitlements
    @Environment(\.dismiss) var dismiss
    let onUnlocked: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.quaternary).frame(width: 36, height: 5).padding(.top, 10)
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 7) { Rectangle().fill(Swiss.red).frame(width: 12, height: 12); Text("D.C.").font(.system(size: 12, weight: .heavy)).tracking(1) }
                    Spacer()
                    Text("ONE-TIME").font(.system(size: 9, weight: .heavy)).tracking(1.4).foregroundStyle(Swiss.ink.opacity(0.45))
                }
                Text("UNLOCK\nDA CAPO").font(.system(size: 38, weight: .black)).tracking(-0.5).lineSpacing(-2)
                    .padding(.top, 6)
                Rectangle().fill(Swiss.ink).frame(height: 3).padding(.top, 8)
                VStack(alignment: .leading, spacing: 0) {
                    row("Create every playlist in your plan")
                    row("Mood playlists, computed on your phone")
                    row("Re-run any time — playlists refresh, never duplicate")
                    row("No subscription, no account, no upsell")
                }
                .padding(.top, 4)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let p = ent.product {
                        Text(p.displayPrice).font(.system(size: 44, weight: .black)).tracking(-1)
                        Text("ONCE. NOT PER MONTH.").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(Swiss.ink.opacity(0.5))
                    } else if ent.loadFailed {
                        Button { Task { await ent.loadProduct() } } label: {
                            Text("Couldn't load the price — tap to retry")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Swiss.red)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ProgressView().tint(Swiss.ink).padding(.vertical, 14)
                    }
                }
                .padding(.top, 16)
                SwissButton(title: ent.purchasing ? "…" : "UNLOCK", disabled: ent.product == nil || ent.purchasing) {
                    Task {
                        await ent.purchase()
                        if ent.unlocked { dismiss(); onUnlocked() }
                    }
                }
                .padding(.top, 14)
                HStack {
                    Button("Restore purchase") {
                        Task {
                            await ent.restore()
                            if ent.unlocked { dismiss(); onUnlocked() }
                        }
                    }
                    Spacer()
                    #if DEBUG
                    Button("Continue free (debug)") { ent.unlocked = true; dismiss(); onUnlocked() }
                    #endif
                }
                .font(.system(size: 12, weight: .semibold)).tint(Swiss.ink.opacity(0.55))
                .padding(.top, 14)
            }
            .foregroundStyle(Swiss.ink)
            .padding(24)
            .background(Swiss.paper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            .padding(.horizontal, 20)
            Spacer()
        }
        .presentationDetents([.large])
    }
    func row(_ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Rectangle().fill(Swiss.red).frame(width: 5, height: 5)
                Text(t).font(.system(size: 14, weight: .semibold))
            }
            .padding(.vertical, 9)
            Rectangle().fill(Swiss.ink.opacity(0.14)).frame(height: 1)
        }
    }
}
