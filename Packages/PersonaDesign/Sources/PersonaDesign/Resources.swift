import SwiftUI

/// Accessor for image assets vended by this package. Feature code asks the design
/// system for art rather than reaching into a bundle by string.
public enum PersonaAsset {
    public static let bundle = Bundle.module

    public static func image(_ name: String) -> Image {
        Image(name, bundle: bundle)
    }
}
