
// Concatenate after PrecisionGeodesy.swift; runs the actual application math on macOS.
let origin = PrecisionGeodesy.Point(latitude: 31.2304, longitude: 121.4737)
let references: [(Double, Double, Double)] = [
    (5, 31.230399999989302, 121.47375248028669),
    (50, 31.23039999892918, 121.47422480286701),
    (500, 31.230399892917443, 121.47894802866631)
]
for (metres, latitude, longitude) in references {
    guard let p = PrecisionGeodesy.offset(from: origin, metres: metres, bearing: 90) else {
        fatalError("Offset failed")
    }
    precondition(abs(p.latitude - latitude) < 1e-8, "Latitude mismatch")
    precondition(abs(p.longitude - longitude) < 1e-8, "Longitude mismatch")
}
precondition(PrecisionGeodesy.offset(from: origin, metres: -1, bearing: 90) == nil)
precondition(PrecisionGeodesy.offset(from: origin, metres: 1, bearing: .nan) == nil)
precondition(PrecisionGeodesy.offset(from: origin, metres: 0, bearing: 90) == origin)
let crossing = PrecisionGeodesy.offset(from: .init(latitude: 0, longitude: 180), metres: 500, bearing: 90)!
precondition(crossing.isValid && crossing.longitude < 0)
print("PASS: Swift WGS-84 5/50/500m reference vectors, invalid inputs and date-line crossing")
