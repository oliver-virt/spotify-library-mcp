import SwiftUI

// MVP paywall. Purchase is a placeholder until the App Store product exists (StoreKit 2 goes here).
// The "beta" link bypasses it on purpose — remove before App Store submission.
final class Entitlements: ObservableObject {
    @AppStorage("sorted.unlocked") var unlocked = false
}

struct PaywallView: View {
    @EnvironmentObject var ent: Entitlements
    @Environment(\.dismiss) var dismiss
    let onUnlocked: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.quaternary).frame(width: 36, height: 5).padding(.top, 8)
            Text("🗂️").font(.system(size: 56)).padding(.top, 8)
            Text("Unlock Sorted").font(.system(.title, design: .rounded).weight(.heavy))
            VStack(alignment: .leading, spacing: 10) {
                bullet("Create every playlist in your plan")
                bullet("Mood playlists, computed on your phone")
                bullet("Re-run any time as your library grows")
                bullet("One-time purchase. No subscription.")
            }
            .padding(.horizontal, 28)
            Spacer()
            Button {
                // TODO: StoreKit 2 purchase of com.olivervirt.sorted.unlock
                ent.unlocked = true
                dismiss(); onUnlocked()
            } label: {
                Text("Unlock — $6.99 once").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).padding(.horizontal)
            Button("Restore purchase") { /* TODO StoreKit 2 restore */ }
                .font(.footnote)
            Button("Continue free (beta)") {
                ent.unlocked = true
                dismiss(); onUnlocked()
            }
            .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 20)
        }
        .presentationDetents([.medium, .large])
    }
    func bullet(_ t: String) -> some View {
        HStack(spacing: 10) { Text("✓").fontWeight(.bold).foregroundStyle(Color(red: 0.83, green: 0.39, blue: 0.10)); Text(t) }
            .font(.system(.subheadline, design: .rounded))
    }
}
