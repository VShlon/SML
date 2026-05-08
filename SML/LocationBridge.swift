import CoreLocation
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// LocationBridge
// Нативный мост CoreLocation -> window.SML_APP.location в WKWebView.
//
// Режим работы:
//   - startWatching() вызывается когда открывается страница account-workday.
//   - CLLocationManager непрерывно обновляет координаты.
//   - При каждом обновлении постится уведомление SMLLocationDidUpdate,
//     WebView инжектирует свежие данные в window.SML_APP.location.
//   - stopWatching() вызывается при уходе со страницы -- battery не тратится.
//
// Это гарантирует что при нажатии "Start / End workday" координаты всегда
// актуальны, а не взяты из кеша момента загрузки страницы.
// ─────────────────────────────────────────────────────────────────────────────

final class LocationBridge: NSObject, CLLocationManagerDelegate {

    static let shared = LocationBridge()

    static let didUpdateNotification = Notification.Name("SMLLocationDidUpdate")

    private let manager = CLLocationManager()
    private(set) var lastLocation: CLLocation?
    private(set) var isWatching: Bool = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Обновлять не чаще чем при смещении на 10 м -- баланс точности и battery
        manager.distanceFilter = 10
    }

    // MARK: - Public

    /// Запускает непрерывное обновление координат.
    /// Если разрешение ещё не выдано -- сначала запрашивает его.
    func startWatching() {
        guard !isWatching else { return }
        isWatching = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // После ответа пользователя сработает locationManagerDidChangeAuthorization
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            // denied / restricted -- уведомляем сразу, чтобы UI показал ошибку
            postUpdate()
        }
    }

    /// Останавливает обновление координат.
    func stopWatching() {
        guard isWatching else { return }
        isWatching = false
        manager.stopUpdatingLocation()
    }

    // MARK: - JS Payload

    /// Готовый JSON для присвоения window.SML_APP.location в WKWebView.
    var jsPayload: String {
        switch manager.authorizationStatus {
        case .denied:
            return #"{"available":false,"authorization":"denied"}"#
        case .restricted:
            return #"{"available":false,"authorization":"restricted"}"#
        case .authorizedWhenInUse, .authorizedAlways:
            if let loc = lastLocation {
                let lat = loc.coordinate.latitude
                let lng = loc.coordinate.longitude
                let acc = max(0, loc.horizontalAccuracy)
                let age = -loc.timestamp.timeIntervalSinceNow // секунды с момента замера
                return "{\"available\":true,\"authorization\":\"granted\","
                    + "\"coords\":{"
                    + "\"latitude\":\(lat),"
                    + "\"longitude\":\(lng),"
                    + "\"accuracy\":\(acc),"
                    + "\"age\":\(Int(age))"
                    + "}}"
            }
            // Разрешение есть, но первый замер ещё не пришёл
            return #"{"available":false,"authorization":"granted"}"#
        default:
            return #"{"available":false,"authorization":"notDetermined"}"#
        }
    }

    // MARK: - Private

    private func postUpdate() {
        NotificationCenter.default.post(name: LocationBridge.didUpdateNotification, object: nil)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Берём самый свежий замер с достаточной точностью (отсекаем кешированные)
        let fresh = locations.filter { -$0.timestamp.timeIntervalSinceNow < 30 }
        if let best = fresh.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) {
            lastLocation = best
        } else if let last = locations.last {
            lastLocation = last
        }
        DispatchQueue.main.async { self.postUpdate() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Не сбрасываем lastLocation -- старые координаты лучше чем ничего
        DispatchQueue.main.async { self.postUpdate() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if isWatching && (status == .authorizedWhenInUse || status == .authorizedAlways) {
            manager.startUpdatingLocation()
        } else {
            DispatchQueue.main.async { self.postUpdate() }
        }
    }
}
