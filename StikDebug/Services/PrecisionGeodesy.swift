import Foundation

/// WGS-84 Vincenty direct solution. Inputs and outputs are decimal degrees/metres.
enum PrecisionGeodesy {
    struct Point: Equatable {
        let latitude: Double
        let longitude: Double
        var isValid: Bool {
            latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
                && (-180...180).contains(longitude)
        }
    }

    static func offset(from point: Point, metres: Double, bearing: Double) -> Point? {
        guard point.isValid, metres.isFinite, (0...100_000).contains(metres), bearing.isFinite else { return nil }
        if metres == 0 { return point }
        let a = 6_378_137.0, f = 1 / 298.257223563
        let b = a * (1 - f), radians = Double.pi / 180
        let alpha = bearing.truncatingRemainder(dividingBy: 360) * radians
        let phi = point.latitude * radians
        let u = atan((1 - f) * tan(phi))
        let sinU = sin(u), cosU = cos(u)
        let sinAlpha = cosU * sin(alpha)
        let cosSquaredAlpha = 1 - sinAlpha * sinAlpha
        let sigma1 = atan2(tan(u), cos(alpha))
        let uSquared = cosSquaredAlpha * (a * a - b * b) / (b * b)
        let A = 1 + uSquared / 16384 * (4096 + uSquared * (-768 + uSquared * (320 - 175 * uSquared)))
        let B = uSquared / 1024 * (256 + uSquared * (-128 + uSquared * (74 - 47 * uSquared)))
        var sigma = metres / (b * A)
        var converged = false
        for _ in 0..<100 {
            let c = cos(2 * sigma1 + sigma), s = sin(sigma), cs = cos(sigma)
            let delta = B * s * (c + B / 4 * (cs * (-1 + 2 * c * c)
                - B / 6 * c * (-3 + 4 * s * s) * (-3 + 4 * c * c)))
            let next = metres / (b * A) + delta
            if abs(next - sigma) < 1e-13 { sigma = next; converged = true; break }
            sigma = next
        }
        guard converged else { return nil }
        let s = sin(sigma), c = cos(sigma)
        let temp = sinU * s - cosU * c * cos(alpha)
        let latitude = atan2(sinU * c + cosU * s * cos(alpha),
                             (1 - f) * sqrt(sinAlpha * sinAlpha + temp * temp))
        let lambda = atan2(s * sin(alpha), cosU * c - sinU * s * cos(alpha))
        let C = f / 16 * cosSquaredAlpha * (4 + f * (4 - 3 * cosSquaredAlpha))
        let cos2 = cos(2 * sigma1 + sigma)
        let L = lambda - (1 - C) * f * sinAlpha * (sigma + C * s * (cos2 + C * c * (-1 + 2 * cos2 * cos2)))
        let longitude = (point.longitude + L / radians + 540).truncatingRemainder(dividingBy: 360) - 180
        let result = Point(latitude: latitude / radians, longitude: longitude)
        return result.isValid ? result : nil
    }
}
