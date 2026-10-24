import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

let a = UUID(), b = UUID(), c = UUID()
let order = [a, b, c]

var state = CatalogBatchClick.State()
state = CatalogBatchClick.apply(state, clicked: a, command: false, shift: false, orderedIDs: order)
check("plain click selects one row and clears the batch",
      state.selected == a && state.batch.isEmpty && state.anchor == a)

state = CatalogBatchClick.apply(state, clicked: b, command: true, shift: false, orderedIDs: order)
check("command-click keeps the plain-clicked row in the batch",
      state.batch == [a, b] && state.selected == a)

state = CatalogBatchClick.apply(state, clicked: b, command: true, shift: false, orderedIDs: order)
check("command-click again removes that row",
      state.batch == [a] && state.selected == a)

state = CatalogBatchClick.apply(state, clicked: c, command: false, shift: true, orderedIDs: order)
check("shift-click extends from the anchor", state.batch == [a, b, c])

state = CatalogBatchClick.apply(state, clicked: b, command: false, shift: false, orderedIDs: order)
check("a later plain click drops the batch", state.batch.isEmpty && state.selected == b)

if failures > 0 { print("\(failures) failed"); exit(1) }
print("BatchClick: all passed")
