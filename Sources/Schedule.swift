import AppKit
import CoreLocation

/// A rule that applies a preset at a time of day, or at sunrise or sunset.
struct ScheduleRule: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable, CaseIterable {
        case time, sunrise, sunset
    }

    var id = UUID()
    var trigger = Trigger.time
    /// For `.time`, minutes after midnight; for sunrise and sunset, minutes before (negative) or after.
    var minutes = 0
    var preset: UUID
}

/// Where sunrise and sunset are worked out for, rounded to about 10 km: plenty for times within a minute or so.
struct ScheduleLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
}

/// Applies presets on a schedule, fading to them over two minutes. Times that pass while the Mac is asleep (or
/// DisplayDeck isn't running) are caught up on wake or launch: the latest one in the past day is applied.
@Observable
final class Schedule {
    private(set) var rules: [ScheduleRule] = []
    private(set) var location: ScheduleLocation?
    /// Why the location couldn't be found, shown in Settings.
    private(set) var locationError: String?
    private(set) var locating = false

    @ObservationIgnored private let manager: DisplayManager
    @ObservationIgnored private let presets: Presets
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fadeTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private let finder = LocationFinder()

    private static let fadeSteps = 24  // Every 5 s, so two minutes.

    init(manager: DisplayManager, presets: Presets) {
        self.manager = manager
        self.presets = presets
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "scheduleRules"),
           let saved = try? JSONDecoder().decode([ScheduleRule].self, from: data) {
            rules = saved
        }
        if let data = defaults.data(forKey: "scheduleLocation") {
            location = try? JSONDecoder().decode(ScheduleLocation.self, from: data)
        }
    }

    func start() {
        // Common modes, so it also runs while a menu or slider is being used.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.check() }
        check()
    }

    // MARK: Editing

    func addRule() {
        guard let preset = presets.all.first else { return }
        rules.append(ScheduleRule(minutes: 21 * 60, preset: preset.id))
        save()
    }

    func update(_ rule: ScheduleRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    func delete(_ id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    /// Rules for a deleted preset go with it.
    func presetDeleted(_ id: UUID) {
        rules.removeAll { $0.preset == id }
        save()
    }

    var needsLocation: Bool { rules.contains { $0.trigger != .time } }

    func findLocation() {
        locating = true
        locationError = nil
        finder.find { [weak self] result in
            guard let self else { return }
            locating = false
            switch result {
            case let .success(found):
                let round = { (value: Double) in (value * 10).rounded() / 10 }
                location = ScheduleLocation(latitude: round(found.coordinate.latitude), longitude: round(found.coordinate.longitude))
                if let data = try? JSONEncoder().encode(location) { UserDefaults.standard.set(data, forKey: "scheduleLocation") }
            case let .failure(failure):
                locationError = failure.message
            }
        }
    }

    /// Today's sunrise and sunset where the schedule's location is, or nil without one (or in polar day or night).
    var todaysSun: (rise: Date, set: Date)? {
        guard let location else { return nil }
        return SunTimes.compute(for: Date(), latitude: location.latitude, longitude: location.longitude)
    }

    // MARK: Running

    private var lastCheck: Date {
        get {
            let saved = UserDefaults.standard.double(forKey: "scheduleLastCheck")
            return saved > 0 ? Date(timeIntervalSince1970: saved) : Date()
        }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "scheduleLastCheck") }
    }

    /// Applies the latest rule whose time came since the last check (looking back at most a day).
    private func check() {
        let now = Date()
        let since = max(lastCheck, now.addingTimeInterval(-86_400))
        lastCheck = now
        var latest: (date: Date, rule: ScheduleRule)?
        for day in [-1, 0].compactMap({ Calendar.current.date(byAdding: .day, value: $0, to: now) }) {
            for rule in rules {
                guard let date = fireDate(of: rule, on: day), date > since, date <= now else { continue }
                if latest == nil || date > latest!.date { latest = (date, rule) }
            }
        }
        if let rule = latest?.rule, let preset = presets.preset(rule.preset) { fade(to: preset) }
    }

    func fireDate(of rule: ScheduleRule, on day: Date) -> Date? {
        let midnight = Calendar.current.startOfDay(for: day)
        switch rule.trigger {
        case .time:
            return Calendar.current.date(byAdding: .minute, value: rule.minutes, to: midnight)
        case .sunrise, .sunset:
            guard let location,
                  let sun = SunTimes.compute(for: midnight.addingTimeInterval(12 * 3600), latitude: location.latitude,
                                             longitude: location.longitude) else { return nil }
            return (rule.trigger == .sunrise ? sun.rise : sun.set).addingTimeInterval(Double(rule.minutes) * 60)
        }
    }

    /// Moves every display in the preset towards its levels in small steps, then applies the preset exactly. Stops if
    /// a display's brightness changes in between: the user (or their keys) took over. Monitors following the built-in
    /// display are left to follow it until the last step.
    private func fade(to preset: Preset) {
        fadeTimer?.invalidate()
        let displays = manager.displays.filter { display in
            !display.isOff && preset.levels[display.monitorKey] != nil && !(DisplayManager.followsBuiltin && display.canFollowBuiltin)
        }
        displays.forEach { $0.refreshBrightness() }
        let start = displays.map { (brightness: $0.brightness, contrast: $0.contrast, volume: $0.volume) }
        var expected = displays.map(\.brightness)
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            for (index, display) in displays.enumerated() {
                display.refreshBrightness()
                if abs(display.brightness - expected[index]) > 0.01 { return timer.invalidate() }
            }
            step += 1
            guard step < Self.fadeSteps else {
                timer.invalidate()
                return presets.apply(preset, to: manager.displays)
            }
            let progress = Double(step) / Double(Self.fadeSteps)
            func blend(_ from: Double?, _ to: Double?) -> Double? {
                guard let from, let to else { return nil }
                return from + (to - from) * progress
            }
            for (index, display) in displays.enumerated() {
                let levels = preset.levels[display.monitorKey]!
                if let value = blend(start[index].brightness, levels.brightness) {
                    display.setBrightness(value)
                    expected[index] = display.brightness
                }
                if let value = blend(start[index].contrast, levels.contrast) { display.setContrast(value) }
                if let value = blend(start[index].volume, levels.volume) { display.setVolume(value) }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: "scheduleRules") }
    }
}

/// Asks macOS for the Mac's location once, asking for permission first if needed.
private final class LocationFinder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, LocationFailure>) -> Void)?

    func find(_ completion: @escaping (Result<CLLocation, LocationFailure>) -> Void) {
        self.completion = completion
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()  // Continues in the authorization callback.
        case .denied, .restricted:
            finish(.failure(LocationFailure(message: "Location access is off for DisplayDeck in System Settings → Privacy & Security → Location Services.")))
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: finish(.failure(LocationFailure(message: "Location access was declined.")))
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last { finish(.success(location)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(LocationFailure(message: "Couldn’t find your location. Check that Location Services is on.")))
    }

    private func finish(_ result: Result<CLLocation, LocationFailure>) {
        let completion = completion
        self.completion = nil
        DispatchQueue.main.async { completion?(result) }
    }
}

/// Why the location couldn't be found, worded for Settings.
struct LocationFailure: Error {
    let message: String
}

/// Sunrise and sunset from the sunrise equation (https://en.wikipedia.org/wiki/Sunrise_equation), accurate to a minute
/// or two, which is all a brightness schedule needs.
enum SunTimes {
    static func compute(for date: Date, latitude: Double, longitude: Double) -> (rise: Date, set: Date)? {
        let radians = Double.pi / 180
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = (julianDay - 2_451_545 + 0.0008).rounded()
        let meanNoon = n - longitude / 360  // Longitude east is positive.
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(anomaly * radians) + 0.02 * sin(2 * anomaly * radians) + 0.0003 * sin(3 * anomaly * radians)
        let eclipticLongitude = (anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2_451_545 + meanNoon + 0.0053 * sin(anomaly * radians) - 0.0069 * sin(2 * eclipticLongitude * radians)
        let declination = asin(sin(eclipticLongitude * radians) * sin(23.4397 * radians))
        let cosHourAngle = (sin(-0.833 * radians) - sin(latitude * radians) * sin(declination))
            / (cos(latitude * radians) * cos(declination))
        guard (-1...1).contains(cosHourAngle) else { return nil }  // The sun doesn't rise or set that day.
        let hourAngle = acos(cosHourAngle) / radians / 360
        let date = { (julian: Double) in Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86_400) }
        return (date(transit - hourAngle), date(transit + hourAngle))
    }
}
