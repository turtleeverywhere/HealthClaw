import SwiftUI
import MapKit
import CoreLocation

struct WorkoutMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    var height: CGFloat = 160

    var body: some View {
        if coordinates.count >= 2 {
            Map(initialPosition: mapPosition, interactionModes: []) {
                MapPolyline(coordinates: coordinates)
                    .stroke(.cyan, lineWidth: 3)

                // Start marker
                if let first = coordinates.first {
                    Annotation("Start", coordinate: first) {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }

                // End marker
                if let last = coordinates.last {
                    Annotation("End", coordinate: last) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
            }
            .mapStyle(.imagery)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)
        }
    }

    private var mapPosition: MapCameraPosition {
        let region = regionForCoordinates(coordinates)
        return .region(region)
    }

    private func regionForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.002),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.002)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
