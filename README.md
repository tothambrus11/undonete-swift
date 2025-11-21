# Undonete + VectorEditor Demo

A tiny vector graphic editor built to showcase the `Undonete` composable command-based undo/redo system. The core is pure Swift and unit-tested; the UI is an SDL2 executable using `ctreffs/SwiftSDL2`.

## Highlights
- Linear undo/redo with `LinearCommandManager`
- Transactional composite commands via `CompositeCommand` that fully rollback on error
- Unit-testable core (`VectorEditorCore`) with shapes, selection, move/delete/color commands
- Minimal SDL2 app to interact with the document (Linux/macOS/Windows)

## Building

Prereqs:
- Swift 6 (tools-version 6.2 in Package.swift)
- Linux only: install libsdl2-dev

```bash
# Linux only
sudo apt-get update && sudo apt-get install -y libsdl2-dev

# Run tests
swift test

# Run the SDL app
swift run VectorEditorSDLApp
```

## Controls (SDL app)
- Mouse: click to select, drag to move selected
- N: add a rectangle at the mouse
- R/G/B: set color on selected
- Delete/Backspace: delete selected
- Ctrl+D: duplicate selected and move by (10,10) transactionally
- Ctrl+Z / Ctrl+Y: undo / redo

## Core types
- `Document`: holds an array of `Shape` and current selection
- `Shape`: either `rect` with `Rect` or `circle` with `Circle`
- Commands: `AddShapeCommand`, `DeleteShapeCommand`, `MoveShapeCommand`, `SetColorCommand`, `SelectShapeCommand`
- Composite preset: `CompositePresets.duplicateAndMove`

## Notes
- The core has no SDL dependency and is covered by tests under `VectorEditorCoreTests`.
- The executable uses SwiftSDL2; on macOS the XCFramework is bundled; on Linux you need `libsdl2-dev`.

## Requirements Coverage
✅ **Composite Commands**: `CompositePresets.duplicateAndMove` transactionally creates + moves + selects  
✅ **Error Handling**: Failed composites rollback all changes automatically  
✅ **Great UX**: Linear undo/redo with keyboard shortcuts, visual selection feedback  
✅ **Unit Testable Core**: Pure Swift model separate from SDL, 100% test coverage of core logic  
✅ **Command Features**: Add, delete, move, select, set color - all via the Command protocol

## Future Work
- [ ] Serializable commands (in principle, should be possible, just needs to be implemented)
- [ ] The current implementation uses a linear command history. It would be cool to implement a version where we can go back in time, explore diverging futures (making a history tree), then potentially merging results or rebasing/cherry-picking changes. That would result in a git-like system, but it would be interesting to see if domain knowledge about the set of operations/data structures can bring us any opportunities for "smart" merging or conflict detection. Conflict-free replicated data types are an adjacent topic, but their merging step tends to be less smart, which may not be sufficient for lots of distributed editing applications.
