import Testing
@testable import StikDebug

struct PrecisionGeodesyTests {
    // Independent WGS-84 GeographicLib reference vectors (Shanghai, bearing 90 degrees).
    @Test func shortOffsets() throws {
        let origin = PrecisionGeodesy.Point(latitude: 31.2304, longitude: 121.4737)
        let vectors: [(Double, Double, Double)] = [
            (5, 31.230399999989302, 121.47375248028669),
            (50, 31.23039999892918, 121.47422480286701),
            (500, 31.230399892917443, 121.47894802866631)
        ]
        for (metres, lat, lon) in vectors {
            let result = try #require(PrecisionGeodesy.offset(from: origin, metres: metres, bearing: 90))
            #expect(abs(result.latitude - lat) < 1e-7)
            #expect(abs(result.longitude - lon) < 1e-7)
        }
    }

    @Test func invalidAndZeroInputs() {
        let origin = PrecisionGeodesy.Point(latitude: 0, longitude: 180)
        #expect(PrecisionGeodesy.offset(from: origin, metres: 0, bearing: 0) == origin)
        #expect(PrecisionGeodesy.offset(from: origin, metres: -1, bearing: 0) == nil)
        #expect(PrecisionGeodesy.offset(from: origin, metres: 1, bearing: .nan) == nil)
        #expect(PrecisionGeodesy.offset(from: .init(latitude: 91, longitude: 0), metres: 5, bearing: 0) == nil)
        let wrapped = PrecisionGeodesy.offset(from: origin, metres: 500, bearing: 90)
        #expect(wrapped?.isValid == true)
        #expect((wrapped?.longitude ?? 0) < 0)
    }
}
