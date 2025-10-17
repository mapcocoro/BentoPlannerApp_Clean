import SwiftUI
import GoogleMobileAds

struct AdMobBannerView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator

        if let rootVC = getRootViewController() {
            banner.rootViewController = rootVC
            print("✅ AdMob: Root view controller set")
        } else {
            print("⚠️ AdMob: Failed to get root view controller")
        }

        let request = GADRequest()
        banner.load(request)
        print("✅ AdMob: Banner ad request sent for ID: \(adUnitID)")

        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, GADBannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: GADBannerView) {
            print("✅ AdMob: Banner ad loaded successfully")
        }

        func bannerView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: Error) {
            print("❌ AdMob: Failed to load banner ad - \(error.localizedDescription)")
        }
    }

    private func getRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return nil
        }
        return scene.windows.first?.rootViewController
    }
}
