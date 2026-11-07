import Foundation

/// A first-launch catalog allows starting on Watch before a phone is available.
/// The phone's full library replaces it later, retaining these canonical IDs.
enum WatchBundledLibrary {
    private static let bundled: WatchWorkoutLibrary = {
        let picks = Bundle.main.url(forResource: "WatchExerciseCatalog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([WatchExercisePick].self, from: $0) } ?? []
        return WatchWorkoutLibrary(generatedAt: Date(timeIntervalSince1970: 0), exercises: picks,
                                   savedWorkouts: [], history: [],
                                   weightUnit: Locale.current.measurementSystem == .us ? .pound : .kilogram)
    }()

    static func load() -> WatchWorkoutLibrary { bundled }
}
