import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

check("CLI is CLI", SidebarItem.cliTools.matchesCategory("CLI"))
check("cli matches regardless of case", SidebarItem.cliTools.matchesCategory("cli"))
check("Client is not CLI", !SidebarItem.cliTools.matchesCategory("Client"))
check("Media is Media", SidebarItem.mediaTools.matchesCategory("Media"))
check("Multimedia is not Media", !SidebarItem.mediaTools.matchesCategory("Multimedia"))
check("AI / Agent is exact", SidebarItem.agentTools.matchesCategory("AI / Agent"))
check("a longer AI name is not AI / Agent", !SidebarItem.agentTools.matchesCategory("AI / Agent tools"))

if failures > 0 { print("\(failures) failed"); exit(1) }
print("SidebarCategory: all passed")
