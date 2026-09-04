//
//  LockScreenWeatherWidgetManager.swift
//  boringNotch
//

import AppKit
import Combine
@preconcurrency import CoreLocation
import Defaults
import SwiftUI

enum LockScreenTemperatureUnit: String, CaseIterable, Defaults.Serializable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
    var title: String { self == .celsius ? "Celsius" : "Fahrenheit" }
    var symbol: String { self == .celsius ? "°C" : "°F" }
}

@MainActor
final class LockScreenWeatherWidgetManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LockScreenWeatherWidgetManager()

    @Published fileprivate var snapshot = LockScreenWeatherSnapshot.placeholder

    private let container = LockScreenWidgetContainer()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var lastFetchDate: Date?
    private var refreshTimer: Timer?
    private var isFetching = false
    private var isLockScreenVisible = false
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        container.configure(
            cornerRadius: 26,
            frame: { context in
                let size = CGSize(width: 360, height: 88)
                return NSRect(
                    x: context.frame.midX - size.width / 2,
                    y: context.frame.midY + 132,
                    width: size.width,
                    height: size.height
                )
            },
            onLockScreenVisibilityChange: { [weak self] visible in
                self?.visibilityChanged(visible)
            }
        ) {
            LockScreenWeatherWidgetView()
        }

        observeSettings()
        updateContainer()
    }

    func requestLocationAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let isAuthorized = manager.authorizationStatus == .authorizedAlways
        Task { @MainActor [weak self] in
            if isAuthorized {
                self?.locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor [weak self] in
            self?.currentLocation = CLLocation(latitude: latitude, longitude: longitude)
            self?.refresh(force: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func observeSettings() {
        Defaults.publisher(.enableLockScreenWeatherWidget)
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateContainer() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenTemperatureUnit)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh(force: true) }
            }
            .store(in: &cancellables)

        Defaults.publisher(.lockScreenWeatherShowsLocation)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshView() }
            }
            .store(in: &cancellables)
    }

    private func visibilityChanged(_ visible: Bool) {
        isLockScreenVisible = visible
        if visible {
            startRefreshTimer()
            refresh()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func updateContainer() {
        let enabled = Defaults[.enableLockScreenWeatherWidget]
        container.setEnabled(enabled)
        if enabled, isLockScreenVisible {
            refresh()
        }
    }

    private func refresh(force: Bool = false) {
        guard isLockScreenVisible, Defaults[.enableLockScreenWeatherWidget], !isFetching else { return }

        let shouldFetch = force
            || lastFetchDate == nil
            || Date().timeIntervalSince(lastFetchDate ?? .distantPast) >= 30 * 60
        guard shouldFetch else { return }

        guard let currentLocation else {
            if locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation()
            }
            return
        }

        isFetching = true
        let unit = Defaults[.lockScreenTemperatureUnit]
        Task { [weak self] in
            guard let self else { return }
            defer { isFetching = false }

            do {
                let weather = try await Self.fetchWeather(at: currentLocation, unit: unit)
                let locationName = await Self.locationName(for: currentLocation)
                guard !Task.isCancelled else { return }
                snapshot = LockScreenWeatherSnapshot(
                    temperature: weather.temperature,
                    symbolName: Self.symbol(for: weather.weatherCode),
                    description: Self.description(for: weather.weatherCode),
                    locationName: locationName,
                    unitSymbol: unit.symbol
                )
                lastFetchDate = Date()
                refreshView()
            } catch {
                refreshView()
            }
        }
    }

    private func refreshView() {
        container.refresh()
    }

    private static func fetchWeather(
        at location: CLLocation,
        unit: LockScreenTemperatureUnit
    ) async throws -> WeatherResponse.Current {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if unit == .fahrenheit {
            components.queryItems?.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit"))
        }

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WeatherResponse.self, from: data).current
    }

    private static func locationName(for location: CLLocation) async -> String? {
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        return place.locality ?? place.administrativeArea ?? place.country
    }

    private static func symbol(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    private static func description(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0: "Clear"
        case 1, 2: "Partly Cloudy"
        case 3: "Overcast"
        case 45, 48: "Foggy"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: "Rain"
        case 71, 73, 75, 77, 85, 86: "Snow"
        case 95, 96, 99: "Thunderstorm"
        default: "Weather"
        }
    }
}

private struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
        }
    }

    let current: Current
}

private struct LockScreenWeatherSnapshot {
    let temperature: Double?
    let symbolName: String
    let description: String
    let locationName: String?
    let unitSymbol: String

    static let placeholder = Self(
        temperature: nil,
        symbolName: "cloud.fill",
        description: "Weather Unavailable",
        locationName: nil,
        unitSymbol: "°C"
    )
}

private struct LockScreenWeatherWidgetView: View {
    @ObservedObject private var weather = LockScreenWeatherWidgetManager.shared

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: weather.snapshot.symbolName)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 3) {
                Text(temperatureText)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(detailText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(width: 360, height: 88)
        .foregroundStyle(.white)
        .background(widgetBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }

    private var temperatureText: String {
        guard let temperature = weather.snapshot.temperature else { return "--" }
        return "\(Int(temperature.rounded()))\(weather.snapshot.unitSymbol)"
    }

    private var detailText: String {
        if Defaults[.lockScreenWeatherShowsLocation], let locationName = weather.snapshot.locationName {
            return locationName
        }
        return weather.snapshot.description
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.clear)
                .glassEffect(.clear.tint(.white.opacity(0.16)), in: .rect(cornerRadius: 26))
        } else {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.28))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                )
        }
    }
}

struct LockScreenWeatherSettings: View {
    @Default(.enableLockScreenWeatherWidget) private var isEnabled
    @Default(.lockScreenTemperatureUnit) private var temperatureUnit
    @Default(.lockScreenWeatherShowsLocation) private var showsLocation

    var body: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                Text("Show weather widget on lock screen")
            }
            .disabled(!Defaults[.showOnLockScreen])

            Picker("Temperature", selection: $temperatureUnit) {
                ForEach(LockScreenTemperatureUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .disabled(!isEnabled)

            Toggle("Show location", isOn: $showsLocation)
                .disabled(!isEnabled)

            Button("Allow Location Access") {
                LockScreenWeatherWidgetManager.shared.requestLocationAccess()
            }
            .disabled(!isEnabled)
        } header: {
            Text("Lock Screen Weather")
        } footer: {
            Text("Weather data is provided by Open-Meteo and refreshes every 30 minutes while the lock screen is visible.")
        }
    }
}
