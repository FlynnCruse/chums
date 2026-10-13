import Foundation
import ImageIO
import CoreGraphics

/// Noodle's frames on the watch: one HEIC image sequence per clip in the app bundle (ChumsWatch/Noodle/<clip>.heics,
/// made by tools/noodle-watch.sh from the Blender renders), decoded a frame at a time off the main thread. The
/// player asks for the frame it needs now; it gets it if it's decoded, the closest one before it otherwise, and the
/// decoder works ahead. A few frames are kept (each 396 × 484 is about 0.75 MB decoded).
final class StretchFrames: @unchecked Sendable {
    static let shared = StretchFrames()
    // two decoders, each with its own image sources, take alternate frames (a frame takes 32–60 ms on a Series 7 and
    // 24 fps leaves 42, so one alone falls behind), a step below the screen's priority: the screen (drawing, the
    // conversation card sliding) always comes first, and a frame that isn't ready shows the one before it
    private let queues = [DispatchQueue(label: "chums.noodle.decode.0", qos: .userInitiated),
                          DispatchQueue(label: "chums.noodle.decode.1", qos: .userInitiated)]
    private let lock = NSLock()
    private var sources: [[String: CGImageSource]] = [[:], [:]]   // sources[i] only touched on queues[i]
    private var cache: [String: CGImage] = [:], order: [String] = []
    private var pending = Set<String>()
    private let keep = 14
    private(set) var decodeMs = 0.0                              // the last decode's time
    // for the event log: decodes and their total time, and frames asked for before they were ready
    private var stats = (decodes: 0, totalMs: 0.0, maxMs: 0.0, asks: 0, misses: 0)
    func takeStats() -> String? {
        lock.lock(); defer { stats = (0, 0, 0, 0, 0); lock.unlock() }
        guard stats.decodes > 0 else { return nil }
        return String(format: "noodle: %d frames decoded, avg %.1f ms, max %.0f ms; %d of %d asked frames weren't ready",
                      stats.decodes, stats.totalMs / Double(stats.decodes), stats.maxMs, stats.misses, stats.asks)
    }

    private static func key(_ clip: String, _ f: Int) -> String { "\(clip):\(f)" }
    /// Offline renders (OfflineRender) wait for each frame, so none is missing from the pictures.
    var waits = false

    /// The frame if it's ready (else nil), and decoding of it and the next two is scheduled.
    func frame(_ clip: String, _ f: Int) -> CGImage? {
        if waits { return decodeNow(clip, f) }
        lock.lock(); let hit = cache[Self.key(clip, f)]; stats.asks += 1; if hit == nil { stats.misses += 1 }; lock.unlock()
        for k in f...(f + 4) { schedule(clip, k) }
        return hit
    }

    /// A clip about to play: its first frames, so the cut doesn't wait.
    func preload(_ clip: String) { if !waits { for k in 0..<6 { schedule(clip, k) } } }

    /// The frame, decoded now if it isn't yet (on its decoder's queue, which owns its image sources).
    private func decodeNow(_ clip: String, _ f: Int) -> CGImage? {
        let k = Self.key(clip, f)
        lock.lock(); let hit = cache[k]; lock.unlock()
        if let hit { return hit }
        guard let im = queues[f % 2].sync(execute: { decode(clip, f, worker: f % 2) }) else { return nil }
        lock.lock(); cache[k] = im; order.append(k); while order.count > keep { cache[order.removeFirst()] = nil }; lock.unlock()
        return im
    }

    private func schedule(_ clip: String, _ f: Int) {
        let k = Self.key(clip, f)
        lock.lock()
        if cache[k] != nil || pending.contains(k) { lock.unlock(); return }
        pending.insert(k); lock.unlock()
        let w = f % 2
        queues[w].async { [self] in
            let t0 = CFAbsoluteTimeGetCurrent()
            let im = decode(clip, f, worker: w)
            decodeMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            lock.lock()
            stats.decodes += 1; stats.totalMs += decodeMs; stats.maxMs = max(stats.maxMs, decodeMs)
            pending.remove(k)
            if let im { cache[k] = im; order.append(k); while order.count > keep { cache[order.removeFirst()] = nil } }
            lock.unlock()
        }
    }

    private func decode(_ clip: String, _ f: Int, worker w: Int) -> CGImage? {
        if sources[w][clip] == nil {
            guard let url = Bundle.main.url(forResource: clip, withExtension: "heics", subdirectory: "Noodle"),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            sources[w][clip] = src
            if sources[w].count > 6 { sources[w] = sources[w].filter { $0.key == clip } }   // a handful of clips open at once
        }
        guard let src = sources[w][clip], f < CGImageSourceGetCount(src) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, f, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Decodes a whole clip in order on the decode queue and reports the times (launch with -noodleBench YES).
    func bench(_ clip: String, done: @escaping (String) -> Void) {
        queues[0].async { [self] in
            var times: [Double] = []
            var f = 0
            while true {
                let t0 = CFAbsoluteTimeGetCurrent()
                guard decode(clip, f, worker: 0) != nil else { break }
                times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000); f += 1
            }
            guard !times.isEmpty else { done("noodle bench: \(clip) didn't decode"); return }
            let sorted = times.sorted(), avg = times.reduce(0, +) / Double(times.count)
            done(String(format: "noodle bench %@: %d frames, first %.0f ms, avg %.1f ms, p95 %.1f ms, max %.0f ms",
                        clip, times.count, times[0], avg, sorted[Int(Double(sorted.count) * 0.95)], sorted.last!))
        }
    }
}
