import SwiftUI
import UIKit

/// A bank's own icon, from its own website (the icon it publishes for
/// iPhones), kept on this phone. Nothing goes to a logo service, so no one
/// else learns which banks you use. No icon: a letter on the bank's color.
struct BankLogo: View {
    let institution: String
    var domain: String? = nil
    var size: CGFloat = 32
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.cardGradient(for: institution)
                    Text(String(institution.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.black.opacity(0.08)))
        .accessibilityHidden(true)
        .task(id: Self.site(institution: institution, domain: domain)) {
            guard let site = Self.site(institution: institution, domain: domain) else { return }
            image = await LogoStore.shared.logo(for: site)
        }
    }

    /// "https://www.chase.com/" → "chase.com".
    static func host(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if let url = URL(string: s.contains("://") ? s : "https://" + s), let h = url.host { s = h }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s.contains(".") ? s : nil
    }

    /// Common banks by name, for accounts the connection didn't give a web address.
    static let knownSites: [(String, String)] = [
        ("chase", "chase.com"), ("bank of america", "bankofamerica.com"), ("bofa", "bankofamerica.com"),
        ("wells fargo", "wellsfargo.com"), ("citi", "citi.com"), ("capital one", "capitalone.com"),
        ("american express", "americanexpress.com"), ("amex", "americanexpress.com"), ("discover", "discover.com"),
        ("ally", "ally.com"), ("usaa", "usaa.com"), ("navy federal", "navyfederal.org"), ("pnc", "pnc.com"),
        ("u.s. bank", "usbank.com"), ("us bank", "usbank.com"), ("td bank", "td.com"), ("sofi", "sofi.com"),
        ("marcus", "marcus.com"), ("goldman", "marcus.com"), ("apple", "apple.com"), ("robinhood", "robinhood.com"),
        ("fidelity", "fidelity.com"), ("vanguard", "vanguard.com"), ("schwab", "schwab.com"), ("barclays", "barclays.com"),
        ("synchrony", "synchrony.com"), ("citizens", "citizensbank.com"), ("truist", "truist.com"), ("chime", "chime.com"),
        ("venmo", "venmo.com"), ("paypal", "paypal.com"), ("bilt", "biltrewards.com"), ("amazon", "amazon.com"),
    ]

    static func site(institution: String, domain: String?) -> String? {
        if let domain = host(domain) { return domain }
        let name = institution.lowercased()
        return knownSites.first { name.contains($0.0) }?.1
    }
}

/// Logos fetched once from the bank's own site and kept in Caches. A site
/// without an icon isn't asked again for a week.
actor LogoStore {
    static let shared = LogoStore()
    private var memory: [String: UIImage] = [:]
    private let folder: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BankLogos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func logo(for site: String) async -> UIImage? {
        if let image = memory[site] { return image }
        let file = folder.appendingPathComponent(site + ".png")
        let miss = folder.appendingPathComponent(site + ".none")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory[site] = image
            return image
        }
        if let when = (try? FileManager.default.attributesOfItem(atPath: miss.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(when) < 7 * 86_400 { return nil }
        guard !ProcessInfo.processInfo.arguments.contains("-demo") else { return nil }
        for candidate in ["https://www.\(site)/apple-touch-icon.png", "https://\(site)/apple-touch-icon.png",
                          "https://www.\(site)/apple-touch-icon-precomposed.png"] {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data), image.size.width >= 32 else { continue }
            if let png = image.pngData() { try? png.write(to: file) }
            memory[site] = image
            return image
        }
        try? Data().write(to: miss)
        return nil
    }
}
