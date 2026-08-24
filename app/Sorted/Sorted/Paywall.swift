import SwiftUI

// MVP paywall. Purchase is a placeholder until the App Store product exists (StoreKit 2 goes here).
// The "beta" link bypasses it on purpose — remove before App Store submission.
final class Entitlements: ObservableObject {
    @AppStorage("dacapo.unlocked") var unlocked = false
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
                    Text("$6.99").font(.system(size: 44, weight: .black)).tracking(-1)
                    Text("ONCE. NOT PER MONTH. ONCE.").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(Swiss.ink.opacity(0.5))
                }
                .padding(.top, 16)
                // TODO: StoreKit 2 purchase of com.olivervirt.dacapo.unlock
                SwissButton(title: "UNLOCK") { ent.unlocked = true; dismiss(); onUnlocked() }
                    .padding(.top, 14)
                HStack {
                    Button("Restore purchase") { /* TODO StoreKit 2 restore */ }
                    Spacer()
                    Button("Continue free (beta)") { ent.unlocked = true; dismiss(); onUnlocked() }
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
