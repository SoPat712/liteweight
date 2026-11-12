#if DEBUG

import UIKit
import QuartzCore

/// Measures the display cadence and main-thread delivery of a single animation.
@MainActor
final class LiteweightFrameMeter: NSObject {
    static let shared = LiteweightFrameMeter()

    private final class Window {
        let label: String
        let startDate = Date()
        let startMediaTime = CACurrentMediaTime()
        var frames = 0
        var lateFrames = 0
        var hitchTimeMS = 0.0
        var frameIntervalsMS: [Double] = []
        var nominalDurationsMS: [Double] = []
        var callbackLatenessSumMS = 0.0
        var maxCallbackLatenessMS = 0.0

        init(label: String) {
            self.label = label
            frameIntervalsMS.reserveCapacity(600)
            nominalDurationsMS.reserveCapacity(600)
        }
    }

    private struct Result: Encodable {
        let label: String
        let startDate: Date
        let endDate: Date
        let startMediaTime: Double
        let endMediaTime: Double
        let frames: Int
        let lateFrames: Int
        let hitchTimeMS: Double
        let worstFrameIntervalMS: Double
        let p95FrameIntervalMS: Double
        let nominalFrameDurationMS: Double
        let meanCallbackLatenessMS: Double
        let maxCallbackLatenessMS: Double
        let build: String
        let maxFPS: Int
        let device: String
    }

    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var previousTargetTimestamp: CFTimeInterval?
    private var window: Window?
    private var finishedWindows: [Result] = []

    var activeLabel: String? { window?.label }

    private override init() {
        super.init()
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(recordFrame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func begin(_ label: String) {
        end()
        start()
        window = Window(label: label)
    }

    func end() {
        guard let window else { return }
        let endDate = Date()
        let endMediaTime = CACurrentMediaTime()
        self.window = nil
        let intervals = window.frameIntervalsMS.sorted()
        let nominal = window.nominalDurationsMS.sorted()
        let median: Double
        if nominal.isEmpty {
            median = 0
        } else if nominal.count.isMultiple(of: 2) {
            median = (nominal[nominal.count / 2 - 1] + nominal[nominal.count / 2]) / 2
        } else {
            median = nominal[nominal.count / 2]
        }
        let p95 = intervals.isEmpty ? 0 : intervals[Int(ceil(Double(intervals.count) * 0.95)) - 1]
        finishedWindows.append(Result(
            label: window.label,
            startDate: window.startDate,
            endDate: endDate,
            startMediaTime: window.startMediaTime,
            endMediaTime: endMediaTime,
            frames: window.frames,
            lateFrames: window.lateFrames,
            hitchTimeMS: window.hitchTimeMS,
            worstFrameIntervalMS: intervals.last ?? 0,
            p95FrameIntervalMS: p95,
            nominalFrameDurationMS: median,
            meanCallbackLatenessMS: window.frames == 0 ? 0 : window.callbackLatenessSumMS / Double(window.frames),
            maxCallbackLatenessMS: window.maxCallbackLatenessMS,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            maxFPS: UIScreen.main.maximumFramesPerSecond,
            device: UIDevice.current.model
        ))
    }

    func reset() {
        do {
            let url = try outputURL()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            finishedWindows.removeAll()
        } catch {
            print("FRAMEMETER reset failed: \(error)")
        }
    }

    func flush() {
        guard !finishedWindows.isEmpty else { return }
        do {
            let url = try outputURL()
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            while let result = finishedWindows.first {
                let json = try encoder.encode(result)
                var line = json
                line.append(0x0A)
                try handle.write(contentsOf: line)
                print("FRAMEMETER " + String(decoding: json, as: UTF8.self))
                finishedWindows.removeFirst()
            }
        } catch {
            print("FRAMEMETER flush failed: \(error)")
        }
    }

    private func outputURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("frame-meter.jsonl")
    }

    @objc private func recordFrame(_ link: CADisplayLink) {
        let callbackLatenessMS = (CACurrentMediaTime() - link.timestamp) * 1_000
        let nominal = link.targetTimestamp - link.timestamp
        defer {
            previousTimestamp = link.timestamp
            previousTargetTimestamp = link.targetTimestamp
        }
        guard let window else { return }
        window.frames += 1
        window.callbackLatenessSumMS += callbackLatenessMS
        window.maxCallbackLatenessMS = max(window.maxCallbackLatenessMS, callbackLatenessMS)
        if let previousTimestamp {
            window.frameIntervalsMS.append(max(0, link.timestamp - previousTimestamp) * 1_000)
        }
        if nominal > 0 {
            window.nominalDurationsMS.append(nominal * 1_000)
            if let previousTargetTimestamp, link.timestamp > previousTargetTimestamp + 0.25 * nominal {
                window.lateFrames += 1
                window.hitchTimeMS += max(0, link.timestamp - previousTargetTimestamp) * 1_000
            }
        }
    }
}

#endif
