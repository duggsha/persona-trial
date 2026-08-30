import Foundation
import MapKit

/// THE one door for rendering a measured quantity in chat cards and any other
/// user-facing surface.
///
/// The contract, which every card is expected to hold: **the backend sends raw
/// SI numbers — meters, Celsius, kilograms — and the device formats them.** Only
/// the device knows the viewer's region, so a pre-formatted "1.2 km" from the
/// server is metric for everyone forever. `PlaceInfo.distanceMeters` is the
/// model: raw on the wire, formatted here.
///
/// This started as one `localizedDistance` with two call sites, which is how the
/// app came to show a metric figure in the assistant's prose next to an imperial
/// one on the card directly below it. If you are about to interpolate a unit
/// suffix into a string — `"\(x) km"`, `"\(t)°C"` — add the case here instead.
///
/// The measurement *system* follows `Locale.current.region`, not the app's UI
/// language pick (`app.uiLanguage`), and that distinction is deliberate: a
/// German-language user in the US still sees miles, and an English-language user
/// in Berlin still sees kilometers. Region decides units; language decides
/// words. The backend applies the identical rule (see `core/units.ts`).
public enum CardUnits {
    /// Format a straight-line distance (in meters) for the viewer's locale.
    ///
    /// The formatter is built per call rather than cached in a `static`:
    /// `MKDistanceFormatter` isn't `Sendable`, so a shared instance trips Swift's
    /// concurrency checks, and creating one is cheap next to the few cards a turn
    /// ever renders.
    public static func localizedDistance(meters: Double) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated // "1.2 km" / "0.7 mi" — compact for a card line
        return formatter.string(fromDistance: max(0, meters))
    }

    /// Format a temperature given in Celsius — the unit every weather API in the
    /// app is asked for — into the viewer's scale.
    ///
    /// Keyed on `.us`, not on `!= .metric`: `Locale.MeasurementSystem` is a
    /// three-way and the UK is its own case, so the "is it metric" phrasing
    /// silently hands Fahrenheit to Britain (the bug this replaced in
    /// `TemperatureUnit.preferred`). The US is the only region wanting °F.
    ///
    /// `includeScale` spells out C/F for prose and detail rows; the compact home
    /// header passes false and shows a bare degree sign, as Apple Weather does.
    public static func localizedTemperature(celsius: Double, includeScale: Bool = true) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = includeScale ? [.naturalScale] : [.temperatureWithoutUnit, .naturalScale]
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: measurement)
    }

    // Weight, speed and volume deliberately have no case here yet: no component
    // renders one, and those figures currently reach the user only as PROSE the
    // agent writes, which the backend's units rule governs (core/units.ts). Add
    // the case when a component actually needs it — following the two above,
    // keyed on `.us` rather than on "is it metric".
}
