import Foundation
import SwiftUI
import Testing
import UIKit
@testable import OffRentLedger

/// The load-in screen fails **silently**, which is the whole reason this file exists.
///
/// A `UILaunchScreen` dictionary naming an asset the catalog does not have does not crash and does
/// not warn: iOS paints the background and leaves the image out, or paints a plain system
/// background and leaves everything out. The app still opens, so nothing in a build log or a test
/// run would ever mention it. The only symptom is that the app starts on a white flash again, and
/// the only way to notice is to be looking at a device at the moment of launch.
///
/// So the things that can quietly come apart are pinned here:
///
/// 1. The `UILaunchScreen` dictionary survived the Info.plist merge. `GENERATE_INFOPLIST_FILE` is
///    on, and re-enabling `INFOPLIST_KEY_UILaunchScreen_Generation` would merge an **empty**
///    dictionary on top of `Config/OffRentLedger-Info.plist` and silently replace it with nothing.
/// 2. Both named assets exist in the shipping catalog.
/// 3. The mark is a square canvas, so iOS centres it rather than stretching it.
/// 4. It has transparency, because the launch screen paints `LaunchBackground` behind it.
///
/// These read the *app* bundle: this suite is app-hosted, so `Bundle.main` is the built app and
/// its catalog and merged Info.plist are the real shipping ones rather than a copy.
struct LaunchScreenTests {

    private var launchScreen: [String: Any]? {
        Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: Any]
    }

    @Test("The shipping Info.plist still declares a launch screen, and it names both keys")
    func launchScreenSurvivedTheMerge() throws {
        let dictionary = try #require(
            launchScreen,
            """
            UILaunchScreen is missing from the merged Info.plist. The usual cause is \
            INFOPLIST_KEY_UILaunchScreen_Generation being switched back on, which merges an empty \
            dictionary over the one in Config/OffRentLedger-Info.plist.
            """
        )
        #expect(dictionary["UIColorName"] as? String == "LaunchBackground")
        #expect(dictionary["UIImageName"] as? String == "LaunchMark")
    }

    @Test("Both named assets are in the shipping catalog")
    func namedAssetsExist() throws {
        let dictionary = try #require(launchScreen)
        let colourName = try #require(dictionary["UIColorName"] as? String)
        let imageName = try #require(dictionary["UIImageName"] as? String)

        #expect(
            UIColor(named: colourName) != nil,
            "UILaunchScreen names the colour '\(colourName)', which the catalog does not have"
        )
        #expect(
            UIImage(named: imageName) != nil,
            "UILaunchScreen names the image '\(imageName)', which the catalog does not have"
        )
    }

    @Test("The mark is square and transparent, so it is centred rather than stretched")
    func markIsASquareWithAlpha() throws {
        let mark = try #require(UIImage(named: "LaunchMark"))
        #expect(
            mark.size.width == mark.size.height,
            "LaunchMark is \(mark.size); a non-square launch image is stretched to the screen"
        )
        let alpha = try #require(mark.cgImage?.alphaInfo)
        #expect(
            alpha != .none && alpha != .noneSkipFirst && alpha != .noneSkipLast,
            "LaunchMark has no alpha channel, so it will paint its own background over LaunchBackground"
        )
    }

    @Test("The credit line's wordmark ships too")
    func wordmarkExists() {
        #expect(
            UIImage(named: "IdleryWordmark") != nil,
            "LaunchSplashView draws IdleryWordmark, which the catalog does not have"
        )
    }

    @Test("The splash draws the mark at exactly the size the launch image is")
    func markSizeIsInStep() throws {
        // `UILaunchScreen` draws its image at the image's own point size and does not scale it.
        // If this constant and the asset disagree, the tag changes size the instant SwiftUI takes
        // over — which is precisely what a launch screen must never do.
        let mark = try #require(UIImage(named: "LaunchMark"))
        #expect(
            mark.size.width == LaunchSplashView.markPoints,
            """
            LaunchMark is \(mark.size.width)pt but LaunchSplashView draws \
            \(LaunchSplashView.markPoints)pt, so the mark will jump at launch
            """
        )
    }
}
