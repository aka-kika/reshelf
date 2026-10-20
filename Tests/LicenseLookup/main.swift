import Foundation

var failures = 0
func expect(_ raw: String, _ name: String, _ strictness: LicenseStrictness, line: Int = #line) {
    guard let info = LicenseInfo.lookup(raw) else {
        print("FAIL line \(line): \"\(raw)\" → nil"); failures += 1; return
    }
    if info.name != name || info.strictness != strictness {
        print("FAIL line \(line): \"\(raw)\" → \(info.name) / \(info.strictness), want \(name) / \(strictness)")
        failures += 1
    }
}

// New licenses: SPDX ids and GitHub's full names.
expect("PostgreSQL", "PostgreSQL", .permissive)
expect("PostgreSQL License", "PostgreSQL", .permissive)
expect("EUPL-1.2", "EUPL-1.2", .strongCopyleft)
expect("eupl-1.1", "EUPL-1.2", .strongCopyleft)
expect("European Union Public License 1.2", "EUPL-1.2", .strongCopyleft)
expect("CC-BY-4.0", "CC-BY", .permissive)
expect("Creative Commons Attribution 4.0 International", "CC-BY", .permissive)
expect("WTFPL", "WTFPL", .permissive)
expect("Do What The F*ck You Want To Public License", "WTFPL", .permissive)

// Spelled-out AGPL and other GNU names.
expect("GNU Affero General Public License v3.0", "AGPL-3.0", .strongCopyleft)
expect("GNU AFFERO GENERAL PUBLIC LICENSE", "AGPL-3.0", .strongCopyleft)
expect("AGPL-3.0-or-later", "AGPL-3.0", .strongCopyleft)
expect("GNU AGPLv3", "AGPL-3.0", .strongCopyleft)
expect("GNU General Public License v3.0", "GPL", .strongCopyleft)
expect("GPLv2", "GPL", .strongCopyleft)
expect("GPL-2.0+", "GPL", .strongCopyleft)
expect("GPL-2.0-only WITH Classpath-exception-2.0", "GPL", .strongCopyleft)
expect("GNU Lesser General Public License v2.1", "LGPL", .weakCopyleft)
expect("LGPL-3.0-only", "LGPL", .weakCopyleft)

// Existing ones show as before.
expect("MIT", "MIT", .permissive)
expect("mit", "MIT", .permissive)
expect("MIT License", "MIT", .permissive)
expect("MIT-0", "MIT", .permissive)
expect("Apache-2.0", "Apache-2.0", .permissive)
expect("Apache License 2.0", "Apache-2.0", .permissive)
expect("Apache License, Version 2.0", "Apache-2.0", .permissive)
expect("BSD-3-Clause", "BSD", .permissive)
expect("BSD 3-Clause \"New\" or \"Revised\" License", "BSD", .permissive)
expect("0BSD", "BSD", .permissive)
expect("ISC", "ISC", .permissive)
expect("BSL-1.0", "Boost (BSL-1.0)", .permissive)
expect("Boost Software License 1.0", "Boost (BSL-1.0)", .permissive)
expect("Zlib", "zlib", .permissive)
expect("Unlicense", "Public domain (CC0 / Unlicense)", .publicDomain)
expect("The Unlicense", "Public domain (CC0 / Unlicense)", .publicDomain)
expect("CC0-1.0", "Public domain (CC0 / Unlicense)", .publicDomain)
expect("Creative Commons Zero v1.0 Universal", "Public domain (CC0 / Unlicense)", .publicDomain)
expect("Public Domain", "Public domain (CC0 / Unlicense)", .publicDomain)
expect("MPL-2.0", "MPL-2.0", .weakCopyleft)
expect("Mozilla Public License 2.0", "MPL-2.0", .weakCopyleft)
expect("EPL-2.0", "EPL-2.0", .weakCopyleft)
expect("Eclipse Public License 2.0", "EPL-2.0", .weakCopyleft)
expect("GPL-3.0", "GPL", .strongCopyleft)
expect("BUSL-1.1", "BUSL-1.1", .restricted)
expect("Business Source License 1.1", "BUSL-1.1", .restricted)
expect("MIT OR Apache-2.0", "MIT", .permissive)

// Missing / unclear stay "no clear license" (row warning, Yard Sale move).
expect("", "No license", .noLicense)
expect("  none ", "No license", .noLicense)
expect("NOASSERTION", "Unclear license", .noLicense)
expect("Other", "Unclear license", .noLicense)

// Unknown text: the "read the LICENSE file" card, never a substring guess.
for raw in ["Elastic-2.0", "SSPL-1.0", "Permitted use only", "Commercial", "CC-BY-NC-4.0",
            "CC-BY-SA-4.0", "Disclaimer", "Proprietary"] {
    expect(raw, "Unrecognized license", .unknown)
}
let u = LicenseInfo.lookup("Elastic-2.0")!
if u.takeaway != "Unrecognized license: read the LICENSE file." || !u.strictness.requiresCaution {
    print("FAIL: unrecognized card text/caution"); failures += 1
}
if LicenseInfo.lookup("Elastic-2.0")?.strictness == .noLicense {
    print("FAIL: unrecognized must not count as no clear license"); failures += 1
}
// Caution banner for the new copyleft ones.
for raw in ["EUPL-1.2", "GNU Affero General Public License v3.0"] where !(LicenseInfo.lookup(raw)!.strictness.requiresCaution) {
    print("FAIL: no caution for \(raw)"); failures += 1
}

if failures == 0 { print("LicenseLookup: all passed") } else { print("LicenseLookup: \(failures) failed"); exit(1) }
// Every license value in Kika's catalog on 2026-10-20 (read-only count):
// none may fall into "Unrecognized" and grow a new caution banner.
for raw in ["MIT", "Apache-2.0", "NOASSERTION", "", "GPL-3.0", "AGPL-3.0", "BSD-3-Clause", "MPL-2.0",
            "GPL-2.0", "BSD-2-Clause", "none", "Unlicense", "MIT-0", "LGPL-3.0", "CC0-1.0", "BSD-3-Clause-Clear"] {
    let info = LicenseInfo.lookup(raw)
    if info?.strictness == .unknown {
        print("FAIL: real catalog value \"\(raw)\" is unrecognized"); failures += 1
    } else {
        print("PASS: real catalog value \"\(raw)\" -> \(info?.name ?? "nil")")
    }
}

