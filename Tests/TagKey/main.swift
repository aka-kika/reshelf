import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

check("C, C++ and C# are three keys",
      SidebarTagKey.key(for: "C") != SidebarTagKey.key(for: "C++")
      && SidebarTagKey.key(for: "C++") != SidebarTagKey.key(for: "C#")
      && SidebarTagKey.key(for: "C") != SidebarTagKey.key(for: "C#"))
check("the letters stay", SidebarTagKey.key(for: "C++") == "c++" && SidebarTagKey.key(for: "C#") == "c#")
check("a hyphen still folds", SidebarTagKey.key(for: "menu-bar") == SidebarTagKey.key(for: "menubar"))

if failures > 0 { print("\(failures) failed"); exit(1) }
print("TagKey: all passed")
