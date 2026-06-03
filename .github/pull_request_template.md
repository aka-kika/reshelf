## What & why

<!-- What does this change, and why? Link any related issue (#123). -->

## How to test

<!-- Manual steps a reviewer can follow. Screenshots/GIFs for UI changes. -->

## Checklist

- [ ] `bash build.sh` → **BUILD SUCCEEDED**
- [ ] Focused on one concern
- [ ] Docs updated if behavior changed (`README.md` / `features.md` / `todo.md`)
- [ ] New `.swift` files are registered in `project.pbxproj` (4 entries each — see [CONTRIBUTING.md](../CONTRIBUTING.md))
- [ ] No secrets committed (tokens/keys stay in Keychain)
- [ ] v1 catalog code doesn't depend on the Intelligence engine (v2 work stays behind the Labs flag)
