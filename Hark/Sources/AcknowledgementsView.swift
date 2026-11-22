import SwiftUI

/// Everything Hark is built on that someone else made, with its license.
struct AcknowledgementsView: View {
    private struct Credit: Identifiable {
        let name: String, use: String, license: String, url: String
        var id: String { name }
    }
    private let credits: [Credit] = [
        Credit(name: "Perch 2.0", use: "The sound-identification model (Google DeepMind).",
               license: "Apache License 2.0", url: "https://www.kaggle.com/models/google/bird-vocalization-classifier"),
        Credit(name: "BirdNET+ 3.0", use: "The second sound-identification model (K. Lisa Yang Center for Conservation Bioacoustics, Cornell Lab of Ornithology, and Chemnitz University of Technology).",
               license: "Apache License 2.0", url: "https://github.com/birdnet-team/model-converter"),
        Credit(name: "BirdNET+ Geomodel 3.0.4", use: "Which species occur where, week by week (K. Lisa Yang Center for Conservation Bioacoustics, Cornell Lab of Ornithology, and Chemnitz University of Technology).",
               license: "Apache License 2.0", url: "https://github.com/birdnet-team/geomodel"),
        Credit(name: "GBIF", use: "Occurrence records behind the range map. GBIF.org, via the GBIF maps API.",
               license: "Data CC0 / CC BY, per dataset", url: "https://www.gbif.org"),
        Credit(name: "eBird", use: "Recent sightings near you, when you add your own eBird API key. Data from the Cornell Lab of Ornithology.",
               license: "eBird API Terms of Use", url: "https://ebird.org"),
        Credit(name: "OpenFauna", use: "Common names, taxonomy and iNaturalist links. Hark's species list is adapted from it (names, groups and icons added) and shared under the same license.",
               license: "CC BY-SA 4.0", url: "https://github.com/tphakala/openfauna"),
        Credit(name: "Font Awesome Free 6.5.2", use: "The frog, locust and spider icons.",
               license: "CC BY 4.0", url: "https://fontawesome.com/license/free"),
        Credit(name: "Silkscreen", use: "The pixel font of the 8-bit look. By Jason Kottke.",
               license: "SIL Open Font License 1.1", url: "https://fonts.google.com/specimen/Silkscreen"),
        Credit(name: "Saira Stencil One", use: "The Duck Blind look's headings. By the Saira Stencil Project Authors (Omnibus-Type).",
               license: "SIL Open Font License 1.1", url: "https://fonts.google.com/specimen/Saira+Stencil+One"),
    ]

    var body: some View {
        List { Group {
            Section {
                ForEach(credits) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name).font(.headline)
                        Text(c.use).font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Text(c.license).font(.caption.weight(.medium))
                            Spacer()
                            if let u = URL(string: c.url) { Link("Website", destination: u).font(.caption) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Hark is free and made for fun. Thank you to everyone who records, shares and labels the sounds of the natural world.")
            }
            Section {
                NavigationLink("Apache License 2.0") { LicenseText(title: "Apache License 2.0", resource: "LICENSE-Apache-2.0") }
            } header: { Text("License texts") }
        }.themedRows() }.themedList()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LicenseText: View {
    let title: String, resource: String
    var body: some View {
        ScrollView {
            Text((Bundle.main.url(forResource: resource, withExtension: "txt")).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
