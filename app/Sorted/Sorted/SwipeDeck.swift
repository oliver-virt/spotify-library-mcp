import SwiftUI
import MusicKit
import AVFoundation

/// Preview player: 30-second clips, polite about interruptions.
@MainActor
final class PreviewPlayer: NSObject, ObservableObject {
    private var player: AVPlayer?
    @Published var playing = false

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
    }
    @objc private func interrupted(_ n: Notification) { stop() }

    func play(_ url: URL) {
        currentURL = url
        player?.pause()
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.volume = 0
        player?.play()
        playing = true
        // quick fade-in so it doesn't stab
        var v: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            v += 0.1
            self?.player?.volume = min(v, 1)
            if v >= 1 { t.invalidate() }
        }
    }
    private var currentURL: URL?

    func togglePause() {
        guard let player else { return }
        if playing { player.pause(); playing = false; Haptics.light() }
        else { player.play(); playing = true; Haptics.light() }
    }

    func restart() {
        guard let url = currentURL else { return }
        Haptics.light()
        play(url)
    }

    func stop() {
        player?.pause(); player = nil; playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct SwipeDeck: View {
    @EnvironmentObject var lib: LibraryModel
    @Environment(\.dismiss) var dismiss
    let picks: [NewSong]
    @StateObject private var player = PreviewPlayer()
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var kept: [NewSong] = []
    @State private var skippedCount = 0
    @State private var saving = false
    @State private var savedCount: Int?

    private var current: NewSong? { index < picks.count ? picks[index] : nil }

    var body: some View {
        ZStack {
            CapTheme.bg.ignoresSafeArea()
            HStack {
                rail(icon: "xmark", label: "SKIP", color: CapTheme.mute, active: offset.width < -30)
                Spacer()
                rail(icon: "plus", label: "ADD", color: CapTheme.red, active: offset.width > 30)
            }
            .padding(.horizontal, 6)
            VStack(spacing: 0) {
                header
                Spacer()
                if let song = current {
                    card(song)
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .gesture(
                            DragGesture()
                                .onChanged { g in
                                    let wasPast = abs(offset.width) > 100
                                    offset = g.translation
                                    if abs(offset.width) > 100 && !wasPast { Haptics.soft() }
                                }
                                .onEnded { g in
                                    if g.translation.width > 100 { decide(keep: true) }
                                    else if g.translation.width < -100 { decide(keep: false) }
                                    else { withAnimation(.snappy) { offset = .zero } }
                                }
                        )
                        .overlay(alignment: .topLeading) { stamp("KEEP", CapTheme.red, offset.width > 40) }
                        .overlay(alignment: .topTrailing) { stamp("SKIP", .gray, offset.width < -40) }
                } else {
                    finished
                }
                if current != nil { playbackControls }
                Spacer()
                if current != nil { buttons }
            }
        }
        .onAppear { playCurrent() }
        .onDisappear { player.stop() }
    }

    func rail(icon: String, label: String, color: Color, active: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
            Text(label).font(.system(size: 10, weight: .heavy)).tracking(1.5)
        }
        .foregroundStyle(color)
        .opacity(active ? 1 : 0.28)
        .scaleEffect(active ? 1.15 : 1)
        .animation(.snappy(duration: 0.2), value: active)
    }

    var header: some View {
        HStack {
            Button { player.stop(); dismiss() } label: {
                Text("Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(CapTheme.mute)
            }
            Spacer()
            Text("\(min(index + 1, picks.count)) / \(picks.count)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(CapTheme.mute)
            Spacer()
            Text("♥ \(kept.count)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(CapTheme.red)
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }

    func card(_ s: NewSong) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(CapTheme.line)
                if let art = s.song.artwork {
                    ArtworkImage(art, width: 280, height: 280).clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Image(systemName: "music.note").font(.system(size: 60)).foregroundStyle(CapTheme.mute)
                }
            }
            .frame(width: 280, height: 280)
            Text(s.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(CapTheme.ink)
                .lineLimit(2).padding(.top, 16)
            Text(s.artist).font(.system(size: 16)).foregroundStyle(CapTheme.mute).lineLimit(1).padding(.top, 2)
            HStack(spacing: 6) {
                Image(systemName: player.playing ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 10))
                Text(s.reason.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(1)
            }
            .foregroundStyle(CapTheme.red)
            .padding(.top, 12)
        }
        .padding(22)
        .frame(width: 324)
        .background(RoundedRectangle(cornerRadius: 22).fill(CapTheme.bubble))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(CapTheme.line))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    func stamp(_ text: String, _ color: Color, _ show: Bool) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .black)).tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(text == "KEEP" ? -12 : 12))
            .padding(28)
            .opacity(show ? 1 : 0.22)
    }

    var playbackControls: some View {
        HStack(spacing: 22) {
            Button { player.restart() } label: {
                Image(systemName: "gobackward").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CapTheme.mute).frame(width: 44, height: 44)
            }
            Button { player.togglePause() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(CapTheme.ink)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(CapTheme.bubble)).overlay(Circle().stroke(CapTheme.line))
            }
            Text(player.playing ? "PREVIEW" : "PAUSED")
                .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                .foregroundStyle(CapTheme.mute).frame(width: 60, alignment: .leading)
        }
        .padding(.top, 18)
    }

    var buttons: some View {
        HStack(spacing: 28) {
            VStack(spacing: 6) {
                Button { decide(keep: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .bold)).foregroundStyle(CapTheme.mute)
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(CapTheme.bubble)).overlay(Circle().stroke(CapTheme.line))
                }
                Text("SKIP").font(.system(size: 9.5, weight: .heavy)).tracking(1.5).foregroundStyle(CapTheme.mute)
            }
            VStack(spacing: 6) {
                Button { decide(keep: true) } label: {
                    Image(systemName: "plus").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(Circle().fill(CapTheme.red))
                }
                Text("ADD TO LIBRARY").font(.system(size: 9.5, weight: .heavy)).tracking(1.2).foregroundStyle(CapTheme.red)
            }
        }
        .padding(.bottom, 34)
    }

    var finished: some View {
        VStack(spacing: 14) {
            Text("♥ \(kept.count)").font(.system(size: 40, weight: .black)).foregroundStyle(CapTheme.red)
            Text(kept.isEmpty ? "Nothing caught you this time." : "\(kept.count) keepers, \(skippedCount) passed.")
                .font(.system(size: 16)).foregroundStyle(CapTheme.ink)
            if let savedCount {
                Text("Added \(savedCount) to your library and ✨ New for you.")
                    .font(.system(size: 13)).foregroundStyle(CapTheme.mute).multilineTextAlignment(.center)
            } else if !kept.isEmpty {
                Button {
                    saving = true
                    Task { savedCount = await lib.discovery.add(kept); saving = false; Haptics.success() }
                } label: {
                    Group {
                        if saving { ProgressView().tint(.white) }
                        else { Text("ADD \(kept.count) TO MY LIBRARY").font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(1.5) }
                    }
                    .foregroundStyle(.white).padding(.horizontal, 26).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 10).fill(CapTheme.red))
                }
                .disabled(saving).padding(.top, 8)
            }
        }
        .padding(32)
    }

    func decide(keep: Bool) {
        guard let song = current else { return }
        if keep { Haptics.medium() } else { Haptics.light() }
        if keep { kept.append(song) } else {
            skippedCount += 1
            var passed = UserDefaults.standard.stringArray(forKey: "dacapo.passed") ?? []
            passed.append("\(song.artist.lowercased())|\(song.title.lowercased())")
            UserDefaults.standard.set(Array(passed.suffix(500)), forKey: "dacapo.passed")
        }
        withAnimation(.snappy(duration: 0.28)) { offset = CGSize(width: keep ? 600 : -600, height: 0) }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            index += 1
            offset = .zero
            if current == nil { Haptics.success() }
            playCurrent()
        }
    }

    func playCurrent() {
        guard let s = current, let url = s.song.previewAssets?.first?.url else { player.stop(); return }
        player.play(url)
    }
}
