import Foundation
import MusicKit
import MediaPlayer

/// Writes a diagnostic trace to Documents/dacapo-diag.txt so it can be pulled off-device.
enum Diag {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dacapo-diag.txt")
    }
    static func log(_ s: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(s)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
        print("DIAG \(s)")
    }
    static func reset() { try? FileManager.default.removeItem(at: url); log("=== run start ===") }

    /// Full MusicKit probe: auth, subscription, storefront, catalog search.
    static func runProbe() async {
        reset()
        log("auth.currentStatus = \(MusicAuthorization.currentStatus)")
        let req = await MusicAuthorization.request()
        log("auth.request -> \(req)")
        log("MPMediaLibrary.authorizationStatus = \(MPMediaLibrary.authorizationStatus().rawValue)")
        log("MPMediaQuery songs = \((MPMediaQuery.songs().items ?? []).count)")

        // Can we read REAL file sizes for downloaded songs, or only estimate?
        let all = MPMediaQuery.songs().items ?? []
        let downloaded = all.filter { !$0.isCloudItem }
        let withURL = downloaded.filter { $0.assetURL != nil }
        var realBytes: Int64 = 0
        for item in withURL.prefix(50) {
            if let u = item.assetURL,
               let v = try? u.resourceValues(forKeys: [.fileSizeKey]), let sz = v.fileSize {
                realBytes += Int64(sz)
            }
        }
        log("library total=\(all.count) downloaded=\(downloaded.count) withAssetURL=\(withURL.count)")
        log("real bytes readable from first \(min(withURL.count,50)) downloaded: \(realBytes) (\(realBytes/1_048_576) MB)")
        if let sample = downloaded.first {
            log("sample downloaded: '\(sample.title ?? "?")' assetURL=\(sample.assetURL?.absoluteString ?? "nil") duration=\(Int(sample.playbackDuration))s")
        }

        do {
            let sub = try await withDeadline(seconds: 8) { try await MusicSubscription.current }
            log("subscription: canPlayCatalog=\(sub.canPlayCatalogContent) canBecomeSub=\(sub.canBecomeSubscriber) hasCloudLibrary=\(sub.hasCloudLibraryEnabled)")
        } catch { log("subscription FAILED: \(error)") }

        do {
            let sf = try await withDeadline(seconds: 8) { try await MusicDataRequest.currentCountryCode }
            log("storefront = \(sf)")
        } catch { log("storefront FAILED: \(error)") }

        do {
            let n = try await withDeadline(seconds: 15) {
                var r = MusicCatalogSearchRequest(term: "radiohead creep", types: [Song.self])
                r.limit = 3
                let resp = try await r.response()
                return resp.songs.map { "\($0.title) — \($0.artistName)" }
            }
            log("catalog search OK: \(n)")
        } catch let e as DeadlineError { log("catalog search TIMED OUT \(e)") }
        catch { log("catalog search FAILED: \(error) | \(error.localizedDescription)") }
        log("=== probe done ===")
    }
}
