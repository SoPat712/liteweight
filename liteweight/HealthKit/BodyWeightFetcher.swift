//
//  BodyWeightFetcher.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 02.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Combine
import HealthKit
import os.log

// MARK: - Local body measurements

/// Canonical units are kilograms, centimetres, and percent.  Keeping the persisted values
/// metric makes display-unit changes lossless and mirrors how workout set weights are stored.
enum BodyMeasurementKind: String, Codable, CaseIterable, Identifiable {
    case bodyWeight
    case bodyFat
    case height
    case neck
    case shoulders
    case chest
    case waist
    case abdomen
    case hips
    case leftBicep
    case rightBicep
    case leftForearm
    case rightForearm
    case leftThigh
    case rightThigh
    case leftCalf
    case rightCalf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyWeight: return "Body weight"
        case .bodyFat: return "Body fat"
        case .height: return "Height"
        case .neck: return "Neck"
        case .shoulders: return "Shoulders"
        case .chest: return "Chest"
        case .waist: return "Waist"
        case .abdomen: return "Abdomen"
        case .hips: return "Hips"
        case .leftBicep: return "Left bicep"
        case .rightBicep: return "Right bicep"
        case .leftForearm: return "Left forearm"
        case .rightForearm: return "Right forearm"
        case .leftThigh: return "Left thigh"
        case .rightThigh: return "Right thigh"
        case .leftCalf: return "Left calf"
        case .rightCalf: return "Right calf"
        }
    }

    var isCircumference: Bool {
        switch self {
        case .bodyWeight, .bodyFat, .height: return false
        default: return true
        }
    }

    func unitLabel(weightUnit: WeightUnit) -> String {
        switch self {
        case .bodyWeight: return weightUnit == .metric ? "kg" : "lb"
        case .bodyFat: return "%"
        default: return weightUnit == .metric ? "cm" : "in"
        }
    }

    func displayValue(from canonicalValue: Double, weightUnit: WeightUnit) -> Double {
        switch self {
        case .bodyWeight:
            return WeightUnit.convert(weight: canonicalValue, from: .metric, to: weightUnit)
        case .bodyFat:
            return canonicalValue
        default:
            return weightUnit == .metric ? canonicalValue : Measurement(value: canonicalValue, unit: UnitLength.centimeters).converted(to: .inches).value
        }
    }

    func canonicalValue(from displayValue: Double, weightUnit: WeightUnit) -> Double {
        switch self {
        case .bodyWeight:
            return WeightUnit.convert(weight: displayValue, from: weightUnit, to: .metric)
        case .bodyFat:
            return displayValue
        default:
            return weightUnit == .metric ? displayValue : Measurement(value: displayValue, unit: UnitLength.inches).converted(to: .centimeters).value
        }
    }

    func validatedCanonicalValue(from input: String, weightUnit: WeightUnit) -> Double? {
        guard let value = Double(input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0 else { return nil }
        let canonical = canonicalValue(from: value, weightUnit: weightUnit)
        return canonical.isFinite && canonical > 0 ? canonical : nil
    }
}

struct BodyMeasurementEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    /// Values indexed by `BodyMeasurementKind.rawValue` for forward-compatible decoding.
    var values: [String: Double]
    /// A compact JPEG kept with the private entry so liteweight backups preserve the
    /// progress photo without introducing a separate sync or file lifecycle.
    var progressPhotoData: Data?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        values: [String: Double],
        progressPhotoData: Data? = nil
    ) {
        self.id = id
        self.date = date
        self.values = values
        self.progressPhotoData = progressPhotoData
    }

    subscript(kind: BodyMeasurementKind) -> Double? {
        get { values[kind.rawValue] }
        set { values[kind.rawValue] = newValue }
    }
}

final class BodyMetricsStore: ObservableObject {
    struct StagedReplacement {
        fileprivate let previousData: Data?
        fileprivate let replacementData: Data
        fileprivate let replacementEntries: [BodyMeasurementEntry]

        var entries: [BodyMeasurementEntry] { replacementEntries }
    }

    static let shared = BodyMetricsStore()

    @Published private(set) var entries: [BodyMeasurementEntry]

    private let userDefaults: UserDefaults
    private let storageKey = LiteweightBackup.bodyMeasurementsStorageKey

    init(userDefaults: UserDefaults = .appGroup) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BodyMeasurementEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        } else {
            entries = []
        }
    }

    var latest: BodyMeasurementEntry? { entries.first }

    func reload() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BodyMeasurementEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        } else {
            entries = []
        }
    }

    func latestValue(for kind: BodyMeasurementKind) -> Double? {
        entries.first { $0[kind] != nil }?[kind]
    }

    @discardableResult
    func save(_ entry: BodyMeasurementEntry, exportToHealth: Bool = true) -> Bool {
        guard entry.date.timeIntervalSinceReferenceDate.isFinite,
              entry.values.values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return false }
        var updated = entries.filter { $0.id != entry.id }
        updated.append(entry)
        updated.sort { $0.date > $1.date }
        guard persist(updated) else { return false }
        if exportToHealth {
            HealthManager.shared.saveBodyMeasurements(entry)
        }
        return true
    }

    func delete(at offsets: IndexSet) {
        let removedEntries = offsets.filter { entries.indices.contains($0) }.map { entries[$0] }
        let removedIDs = Set(removedEntries.map(\.id))
        guard persist(entries.filter { !removedIDs.contains($0.id) }) else { return }
        removedEntries.forEach(HealthManager.shared.deleteBodyMeasurements)
    }

    func delete(id: UUID) {
        let removedEntries = entries.filter { $0.id == id }
        guard persist(entries.filter { $0.id != id }) else { return }
        removedEntries.forEach(HealthManager.shared.deleteBodyMeasurements)
    }

    func mergeHealthValues(_ values: [BodyMeasurementKind: Double], date: Date) {
        guard !values.isEmpty else { return }
        var dictionary: [String: Double] = [:]
        values.forEach { dictionary[$0.key.rawValue] = $0.value }
        save(BodyMeasurementEntry(date: date, values: dictionary), exportToHealth: false)
    }

    func stageReplacement(with entries: [BodyMeasurementEntry]) throws -> StagedReplacement {
        guard entries.allSatisfy({ entry in
            entry.date.timeIntervalSinceReferenceDate.isFinite
                && entry.values.values.allSatisfy { $0.isFinite && $0 > 0 }
        }) else {
            throw HevyCSVError.couldNotSaveMeasurements
        }
        let sorted = entries.sorted { $0.date > $1.date }
        do {
            return StagedReplacement(
                previousData: userDefaults.data(forKey: storageKey),
                replacementData: try JSONEncoder().encode(sorted),
                replacementEntries: sorted
            )
        } catch {
            throw HevyCSVError.couldNotSaveMeasurements
        }
    }

    /// UserDefaults does not expose durable-write failures. Encoding is done
    /// during staging; this method only installs the already encoded value.
    func write(_ replacement: StagedReplacement) {
        userDefaults.set(replacement.replacementData, forKey: storageKey)
    }

    func publish(_ replacement: StagedReplacement) {
        entries = replacement.replacementEntries
    }

    func rollback(_ replacement: StagedReplacement) {
        if let previousData = replacement.previousData {
            userDefaults.set(previousData, forKey: storageKey)
        } else {
            userDefaults.removeObject(forKey: storageKey)
        }
    }

    private func persist(_ updated: [BodyMeasurementEntry]) -> Bool {
        do {
            let data = try JSONEncoder().encode(updated)
            userDefaults.set(data, forKey: storageKey)
            entries = updated
            return true
        } catch {
            os_log("Could not encode body measurements: %@", log: .health, type: .error, error.localizedDescription)
            return false
        }
    }
}

class BodyWeightFetcher: ObservableObject {
    @Published var bodyWeight: Double? // always metric (kg)
    
    private let date: Date?
    
    init(date: Date?) {
        self.date = date
    }
    
    // gets the closest body weight +-1 day to date
    func fetchBodyWeight() {
        HealthManager.shared.requestReadBodyWeightPermission { authorization in
            guard case .success = authorization else { return }
            guard let date = self.date else { return }
            
            guard let sampleType = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return }
            let predicate = HKQuery.predicateForSamples(
                withStart: Calendar.current.date(byAdding: .day, value: -1, to: date),
                end: Calendar.current.date(byAdding: .day, value: 1, to: date)
            )
            
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil) { (query, samples, error) in
                    guard let samples = samples as? [HKQuantitySample] else {
                        if let error = error { print(error) }
                        return
                    }
                    let _closestSample = Self.closestSample(to: date, in: samples)
                    guard let closestSample = _closestSample else { return }
                    
                    let kiloUnit = HKUnit.gramUnit(with: .kilo)
                    guard closestSample.quantity.is(compatibleWith: kiloUnit) else { return }
                    
                    DispatchQueue.main.async {
                        self.bodyWeight = closestSample.quantity.doubleValue(for: kiloUnit)
                    }
            }
            HealthManager.shared.healthStore.execute(query)
        }
    }

    static func closestSample(to date: Date, in samples: [HKQuantitySample]) -> HKQuantitySample? {
        samples.min {
            abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date))
        }
    }
}
