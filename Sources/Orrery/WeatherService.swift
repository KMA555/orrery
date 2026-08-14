import Foundation
import SwiftUI

struct DayForecast: Identifiable, Equatable {
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    var id: Date { date }
}

struct WeatherSnapshot: Equatable {
    var temperature: Double
    var apparent: Double
    var humidity: Int
    var wind: Double
    var code: Int
    var sunrise: String
    var sunset: String
    var days: [DayForecast]
    var updated: Date
}

/// Open-Meteo（APIキー不要）から現在の天気と数日ぶんの予報を取る。
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var failed = false

    private var ticker: Timer?

    func start() {
        guard ticker == nil else { return }
        Task { await refresh() }
        let timer = Timer(timeInterval: HUDConfig.weatherInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func refresh() async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(HUDConfig.latitude)),
            URLQueryItem(name: "longitude", value: String(HUDConfig.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "4")
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            snapshot = Self.snapshot(from: response)
            failed = false
        } catch {
            failed = snapshot == nil
        }
    }

    private static func snapshot(from response: Response) -> WeatherSnapshot {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var days: [DayForecast] = []
        for index in response.daily.time.indices {
            guard let date = formatter.date(from: response.daily.time[index]) else { continue }
            days.append(DayForecast(date: date,
                                    code: response.daily.weather_code[index],
                                    high: response.daily.temperature_2m_max[index],
                                    low: response.daily.temperature_2m_min[index]))
        }
        return WeatherSnapshot(temperature: response.current.temperature_2m,
                               apparent: response.current.apparent_temperature,
                               humidity: response.current.relative_humidity_2m,
                               wind: response.current.wind_speed_10m,
                               code: response.current.weather_code,
                               sunrise: String(response.daily.sunrise.first?.suffix(5) ?? "--:--"),
                               sunset: String(response.daily.sunset.first?.suffix(5) ?? "--:--"),
                               days: days,
                               updated: Date())
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let relative_humidity_2m: Int
            let apparent_temperature: Double
            let weather_code: Int
            let wind_speed_10m: Double
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]
            let sunset: [String]
        }
        let current: Current
        let daily: Daily
    }
}

/// WMOの天気コードを日本語とアイコンに変換する。
enum WeatherCode {
    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "快晴"
        case 1: return "晴れ"
        case 2: return "薄曇り"
        case 3: return "曇り"
        case 45, 48: return "霧"
        case 51, 53, 55: return "霧雨"
        case 56, 57: return "着氷性の霧雨"
        case 61: return "弱い雨"
        case 63: return "雨"
        case 65: return "強い雨"
        case 66, 67: return "着氷性の雨"
        case 71, 73, 75: return "雪"
        case 77: return "霧雪"
        case 80, 81: return "にわか雨"
        case 82: return "激しいにわか雨"
        case 85, 86: return "にわか雪"
        case 95: return "雷雨"
        case 96, 99: return "雹をともなう雷雨"
        default: return "—"
        }
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.min.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 67, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }
}
