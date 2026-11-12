//
//  WeightUnit.swift
//  Sunrise Fit
//
//  Created by Karim Abou Zeid on 16.07.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation

enum WeightUnit: String, CaseIterable, Hashable {
    case metric
    case imperial
    
    var title: String {
        switch self {
        case .metric:
            return "Metric (kg)"
        case .imperial:
            return "Imperial (lb)"
        }
    }
    
    var unit: UnitMass {
        switch self {
        case .metric:
            return .kilograms
        case .imperial:
            return .pounds
        }
    }
}

extension WeightUnit {
    var minimumFractionDigits: Int { 0 }
    var maximumFractionDigits: Int { 3 }
    var defaultFractionDigits: Int {
        switch self {
        case .metric:
            return 1
        case .imperial:
            return 0
        }
    }
    
    var numberFormatter: NumberFormatter {
        numberFormatter(locale: .current, grouped: false)
    }
    
    /// Grouped presentation values; numeric editors keep `numberFormatter`.
    var displayNumberFormatter: NumberFormatter {
        numberFormatter(locale: .current, grouped: true)
    }

    var formatter: MeasurementFormatter {
        formatter(locale: .current)
    }

    /// Formatters handed to callers are always new. A copy of a cached formatter still shares
    /// its ICU state, and using one off the main thread while the cache formatted crashed
    /// (build 132), so only `format(weight:from:to:)` uses the cache, under its lock.
    func numberFormatter(locale: Locale, grouped: Bool) -> NumberFormatter {
        Self.makeNumberFormatter(minimumFractionDigits: minimumFractionDigits,
                                 maximumFractionDigits: maximumFractionDigits, locale: locale, grouped: grouped)
    }

    func formatter(locale: Locale) -> MeasurementFormatter {
        Self.makeMeasurementFormatter(numberFormatter: numberFormatter(locale: locale, grouped: true), locale: locale)
    }

    fileprivate static func makeNumberFormatter(minimumFractionDigits: Int, maximumFractionDigits: Int,
                                                locale: Locale, grouped: Bool) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.allowsFloats = true
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        if grouped {
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = true
        }
        return formatter
    }

    fileprivate static func makeMeasurementFormatter(numberFormatter: NumberFormatter, locale: Locale) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter = numberFormatter
        return formatter
    }

    private static let formatterCache = FormatterCache()

    private final class FormatterCache {
        private struct NumberKey: Hashable {
            let unit: WeightUnit
            let localeIdentifier: String
            let minimumFractionDigits: Int
            let maximumFractionDigits: Int
            let style: NumberFormatter.Style
            let usesGroupingSeparator: Bool

            init(unit: WeightUnit, locale: Locale, grouped: Bool) {
                self.unit = unit
                localeIdentifier = locale.identifier
                minimumFractionDigits = unit.minimumFractionDigits
                maximumFractionDigits = unit.maximumFractionDigits
                style = grouped ? .decimal : .none
                usesGroupingSeparator = grouped
            }
        }

        private struct MeasurementKey: Hashable {
            let number: NumberKey
            let unitOptions: MeasurementFormatter.UnitOptions.RawValue
            let style: Formatter.UnitStyle
        }

        private let lock = NSLock()
        private var measurements: [MeasurementKey: MeasurementFormatter] = [:]
        private var localeObserver: NSObjectProtocol?

        init() {
            localeObserver = NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.measurements.removeAll()
                self.lock.unlock()
            }
        }

        deinit {
            if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) }
        }

        func string(from measurement: Measurement<UnitMass>, unit: WeightUnit, locale: Locale) -> String {
            lock.lock()
            defer { lock.unlock() }
            return cachedMeasurementFormatter(unit: unit, locale: locale).string(from: measurement)
        }

        private func cachedMeasurementFormatter(unit: WeightUnit, locale: Locale) -> MeasurementFormatter {
            let key = MeasurementKey(number: NumberKey(unit: unit, locale: locale, grouped: true),
                                     unitOptions: MeasurementFormatter.UnitOptions.providedUnit.rawValue,
                                     style: .medium)
            if let formatter = measurements[key] { return formatter }
            let formatter = WeightUnit.makeMeasurementFormatter(
                numberFormatter: unit.numberFormatter(locale: locale, grouped: true), locale: locale)
            measurements[key] = formatter
            return formatter
        }
    }
}

extension WeightUnit {
    static func sanitizedDecimalInput(
        _ input: String,
        maximumFractionDigits: Int,
        decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
        groupingSeparator: String = Locale.current.groupingSeparator ?? ","
    ) -> String {
        // With comma decimals, distinguish pasted thousands ("1.005") from
        // a period entered on the keypad ("2.5"). A native decimal takes priority.
        let periodGroups = input.filter { $0.wholeNumberValue != nil || $0 == "." }
            .split(separator: ".", omittingEmptySubsequences: false)
        let isGroupedInteger = periodGroups.count > 1
            && (1...3).contains(periodGroups[0].count)
            && periodGroups.dropFirst().allSatisfy { $0.count == 3 }
        let acceptsKeypadDecimal = decimalSeparator == ","
            && !input.contains(decimalSeparator)
            && (groupingSeparator != "." || !isGroupedInteger)
        var result = ""
        var hasDecimalSeparator = false
        var fractionDigitCount = 0

        for character in input {
            if let digit = character.wholeNumberValue {
                if hasDecimalSeparator {
                    guard fractionDigitCount < maximumFractionDigits else { continue }
                    fractionDigitCount += 1
                }
                result.append(contentsOf: String(digit))
            } else if String(character) == decimalSeparator || (character == "." && acceptsKeypadDecimal) {
                guard !hasDecimalSeparator else { continue }
                if result.isEmpty { result = "0" }
                if maximumFractionDigits > 0 { result.append(contentsOf: decimalSeparator) }
                hasDecimalSeparator = true
            }
        }
        return result
    }

    static func convert(weight: Double, from: WeightUnit, to: WeightUnit) -> Double {
        Measurement(value: weight, unit: from.unit).converted(to: to.unit).value
    }
    
    static func format(weight: Double, from: WeightUnit, to: WeightUnit) -> String {
        format(weight: weight, from: from, to: to, locale: .current)
    }

    static func format(weight: Double, from: WeightUnit, to: WeightUnit, locale: Locale) -> String {
        formatterCache.string(from: Measurement(value: weight, unit: from.unit).converted(to: to.unit),
                              unit: to, locale: locale)
    }
}

extension WeightUnit {
    var barbellIncrement: Double {
        switch self {
        case .metric:
            return 2.5 // 2x 1.25 kg
        case .imperial:
            return 5 // 2x 2.5 lb
        }
    }

    /// What one +/- press changes in the logger, in either unit. The owner asked
    /// for 2.5 lb rather than a plate pair; suggestions and warm-ups keep barbellIncrement.
    var adjustmentStep: Double { 2.5 }

    var barbellWeight: Double {
        switch self {
        case .metric:
            return 20
        case .imperial:
            return 45
        }
    }
}
