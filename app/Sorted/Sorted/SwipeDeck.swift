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

    private var dragProgress: Double { min(1, abs(offset.width) / 110) }

    var body: some View {
        ZStack {
            CapTheme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                ZStack {
                    // next card peeking behind (standard deck convention)
                    if index + 1 < picks.count {
                        card(picks[index + 1])
                            .scaleEffect(0.94)
                            .offset(y: 14)
                            .opacity(0.55)
                    }
                    if let song = current {
                        card(song)
                            .overlay(alignment: .topLeading) {
                                stamp("ADD", CapTheme.red, -14)
                                    .opacity(offset.width > 20 ? dragProgress : 0)
                                    .padding(18)
                            }
                            .overlay(alignment: .topTrailing) {
                                stamp("SKIP", .white.opacity(0.85), 14)
                                    .opacity(offset.width < -20 ? dragProgress : 0)
                                    .padding(18)
                            }
                            .offset(offset)
                            .rotationEffect(.degrees(Double(offset.width / 25)))
                            .gesture(
                                DragGesture()
                                    .onChanged { g in
                                        let wasPast = abs(offset.width) > 110
                                        offset = g.translation
                                        if abs(offset.width) > 110 && !wasPast { Haptics.soft() }
                                    }
                                    .onEnded { g in
                                        if g.translation.width > 110 { decide(keep: true) }
                                        else if g.translation.width < -110 { decide(keep: false) }
                                        else { withAnimation(.snappy) { offset = .zero } }
                                    }
                            )
                    } else {
                        finished
                    }
                }
                Spacer(minLength: 8)
                if current != nil {
                    playbackControls
                    buttons
                }
            }
        }
        .onAppear { playCurrent() }
        .onDisappear { player.stop() }
    }

    var header: some View {
        HStack {
            Button { player.stop(); dismiss() } label: {
                Text("Done").font(.system(size: 15, weight: .semibold)).foregroundStyle(CapTheme.mute)
            }
            Spacer()
            Text("\(min(index + 1, picks.count)) of \(picks.count)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(CapTheme.mute)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12))
                Text("\(kept.count)").font(.system(size: 13, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(CapTheme.red)
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
    }

    func card(_ s: NewSong) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(CapTheme.line)
                if let art = s.song.artwork {
                    ArtworkImage(art, width: 340, height: 340)
                } else {
                    Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(CapTheme.mute)
                }
            }
            .frame(height: 340)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title).font(.system(size: 21, weight: .heavy)).foregroundStyle(CapTheme.ink).lineLimit(1)
                Text(s.artist).font(.system(size: 16)).foregroundStyle(CapTheme.mute).lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: player.playing ? "speaker.wave.2.fill" : "pause.circle").font(.system(size: 10))
                    Text(s.reason.uppercased()).font(.system(size: 9.5, weight: .heavy)).tracking(1).lineLimit(1)
                }
                .foregroundStyle(CapTheme.red)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(width: 340)
        .background(CapTheme.bubble)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CapTheme.line))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
    }

    func stamp(_ text: String, _ color: Color, _ angle: Double) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .black)).tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }

    var playbackControls: some View {
        HStack(spacing: 20) {
            Button { player.restart() } label: {
                Image(systemName: "gobackward").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CapTheme.mute).frame(width: 44, height: 44)
            }
            Button { player.togglePause() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(CapTheme.ink)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(CapTheme.bubble)).overlay(Circle().stroke(CapTheme.line))
            }
            Text(player.playing ? "PREVIEW" : "PAUSED")
                .font(.system(size: 9.5, weight: .heavy)).tracking(1.4)
                .foregroundStyle(CapTheme.mute).frame(width: 58, alignment: .leading)
        }
        .padding(.top, 14).padding(.bottom, 6)
    }

    var buttons: some View {
        HStack(spacing: 44) {
            Button { decide(keep: false) } label: {
                Image(systemName: "xmark").font(.system(size: 24, weight: .bold)).foregroundStyle(CapTheme.mute)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(CapTheme.bubble)).overlay(Circle().stroke(CapTheme.line))
            }
            Button { decide(keep: true) } label: {
                Image(systemName: "plus").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 72, height: 72).background(Circle().fill(CapTheme.red))
                    .shadow(color: CapTheme.red.opacity(0.4), radius: 12, y: 4)
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Text("swipe left to skip · right to add")
                .font(.system(size: 10.5)).foregroundStyle(CapTheme.mute.opacity(0.6))
                .offset(y: 14)
        }
        .padding(.bottom, 28)
    }

    var finished: some View {
        VStack(spacing: 14) {
            Text("\(kept.count)").font(.system(size: 52, weight: .black)).foregroundStyle(CapTheme.red)
            Text(kept.isEmpty ? "Nothing caught you this time." : "keepers, \(skippedCount) passed")
                .font(.system(size: 16)).foregroundStyle(CapTheme.ink)
            if let savedCount {
                Text("Added \(savedCount) to your library and ✨ New for you.")
                    .font(.system(size: 13)).foregroundStyle(CapTheme.mute).multilineTextAlignment(.center)
            } else if !kept.isEmpty {
                Button {
                    saving = true
                    Task { savedCount = await lib.discovery.add(kept); saving = false; Haptics.success(); await lib.scan() }
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
