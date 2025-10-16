import Foundation
import Undonete

public enum VectorError: Error, Equatable, Sendable {
    case notFound
    case invalidOperation(String)
}

public struct AddShapeCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = Shape

    let shape: Shape

    public static func execute(instruction: Shape, on model: inout Document) throws -> (
        doneCommand: AddShapeCommand, hadEffect: Bool
    ) {
        var inserted = instruction
        // ensure unique ID by regenerating if conflicting
        let existing = model.shapes.contains { $0.id == instruction.id }
        if existing {
            switch instruction {
            case .rect(_, let r): inserted = .rect(.rect(UUID()), r)
            case .circle(_, let c): inserted = .circle(.circle(UUID()), c)
            }
        }
        let cmd = AddShapeCommand(shape: inserted)
        cmd.redo(on: &model)
        return (cmd, true)
    }

    public func undo(on model: inout Document) {
        if let idx = model.indexOfShape(id: shape.id) {
            model.shapes.remove(at: idx)
            model.selected.remove(shape.id)
        }
    }

    public func redo(on model: inout Document) {
        model.shapes.append(shape)
    }
}

public struct DeleteShapeCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = ShapeID

    let id: ShapeID
    let removed: Shape
    let removedIndex: Int

    public static func execute(instruction: ShapeID, on model: inout Document) throws -> (
        doneCommand: DeleteShapeCommand, hadEffect: Bool
    ) {
        guard let idx = model.indexOfShape(id: instruction) else {
            return (
                DeleteShapeCommand(
                    id: instruction,
                    removed: .rect(
                        .rect(UUID()), Rect(x: 0, y: 0, width: 0, height: 0, color: .black)),
                    removedIndex: -1), false
            )
        }
        let shape = model.shapes.remove(at: idx)
        let cmd = DeleteShapeCommand(id: instruction, removed: shape, removedIndex: idx)
        return (cmd, true)
    }

    public func undo(on model: inout Document) {
        model.shapes.insert(removed, at: removedIndex)
    }

    public func redo(on model: inout Document) {
        if let idx = model.indexOfShape(id: id) {
            model.shapes.remove(at: idx)
        }
    }
}

public struct MoveShapeCommand: Command, Sendable {
    public typealias Model = Document
    public struct Instruction: Sendable {
        public var id: ShapeID
        public var offset: Point
        public init(id: ShapeID, offset: Point) {
            self.id = id
            self.offset = offset
        }
        public init(id: ShapeID, dx: Double, dy: Double) {
            self.id = id
            self.offset = Point(x: dx, y: dy)
        }
    }

    let id: ShapeID
    let offset: Point

    public static func execute(instruction: Instruction, on model: inout Document) throws -> (
        doneCommand: MoveShapeCommand, hadEffect: Bool
    ) {
        guard let idx = model.indexOfShape(id: instruction.id) else { throw VectorError.notFound }
        let originalShape = model.shapes[idx]
        var shape = originalShape
        switch shape {
        case .rect(let id, var r):
            r.origin += instruction.offset
            shape = .rect(id, r)
        case .circle(let id, var c):
            c.center += instruction.offset
            shape = .circle(id, c)
        }
        if shape == originalShape {
            return (MoveShapeCommand(id: instruction.id, offset: .zero), false)
        }
        model.shapes[idx] = shape
        let cmd = MoveShapeCommand(id: instruction.id, offset: instruction.offset)
        return (cmd, true)
    }

    public func undo(on model: inout Document) {
        _ = try? MoveShapeCommand.execute(
            instruction: .init(id: id, offset: Point(x: -offset.x, y: -offset.y)), on: &model)
    }

    public func redo(on model: inout Document) {
        _ = try? MoveShapeCommand.execute(instruction: .init(id: id, offset: offset), on: &model)
    }
}

public struct SetColorCommand: Command, Sendable {
    public typealias Model = Document
    public struct Instruction: Sendable {
        public var id: ShapeID
        public var color: Color
        public init(id: ShapeID, color: Color) {
            self.id = id
            self.color = color
        }
    }

    let id: ShapeID
    let oldColor: Color
    let newColor: Color

    public static func execute(instruction: Instruction, on model: inout Document) throws -> (
        doneCommand: SetColorCommand, hadEffect: Bool
    ) {
        guard let idx = model.indexOfShape(id: instruction.id) else { throw VectorError.notFound }
        switch model.shapes[idx] {
        case .rect(let id, var r):
            if r.color == instruction.color {
                return (
                    SetColorCommand(id: instruction.id, oldColor: r.color, newColor: r.color), false
                )
            }
            let old = r.color
            r.color = instruction.color
            model.shapes[idx] = .rect(id, r)
            return (
                SetColorCommand(id: instruction.id, oldColor: old, newColor: instruction.color),
                true
            )
        case .circle(let id, var c):
            if c.color == instruction.color {
                return (
                    SetColorCommand(id: instruction.id, oldColor: c.color, newColor: c.color), false
                )
            }
            let old = c.color
            c.color = instruction.color
            model.shapes[idx] = .circle(id, c)
            return (
                SetColorCommand(id: instruction.id, oldColor: old, newColor: instruction.color),
                true
            )
        }
    }

    public func undo(on model: inout Document) {
        _ = try? SetColorCommand.execute(instruction: .init(id: id, color: oldColor), on: &model)
    }

    public func redo(on model: inout Document) {
        _ = try? SetColorCommand.execute(instruction: .init(id: id, color: newColor), on: &model)
    }
}

public struct SelectAndBringToFront: CompositeActor {
    public static func compositeExecute(
        instruction shapeID: ShapeID?, on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        if let shapeID = shapeID {
            // First bring to front, then select
            _ = try executor.execute(
                command: BringToFrontCommand.self, instruction: shapeID, on: &model)
            _ = try executor.execute(
                command: SelectShapeCommand.self, instruction: [shapeID], on: &model)
        } else {
            // Just deselect if instruction is nil
            _ = try executor.execute(
                command: SelectShapeCommand.self, instruction: [], on: &model)
        }
    }
}
public typealias SelectAndBringToFrontCommand = CompositeCommandFromActor<SelectAndBringToFront>

public struct BringToFrontCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = ShapeID

    let id: ShapeID
    let originalIndex: Int

    public static func execute(instruction: ShapeID, on model: inout Document) throws -> (
        doneCommand: BringToFrontCommand, hadEffect: Bool
    ) {
        guard let idx = model.indexOfShape(id: instruction) else { throw VectorError.notFound }
        
        // If it's already at the front (last position), no change needed
        if idx == model.shapes.count - 1 {
            return (BringToFrontCommand(id: instruction, originalIndex: idx), false)
        }
        
        let shape = model.shapes.remove(at: idx)
        model.shapes.append(shape)  // Move to end (front of rendering order)
        model.maxZIndex += 1
        
        return (BringToFrontCommand(id: instruction, originalIndex: idx), true)
    }

    public func undo(on model: inout Document) {
        // Find the shape and move it back to its original position
        if let currentIndex = model.indexOfShape(id: id) {
            let shape = model.shapes.remove(at: currentIndex)
            model.shapes.insert(shape, at: originalIndex)
        }
    }

    public func redo(on model: inout Document) {
        // Bring the shape to front again
        _ = try? BringToFrontCommand.execute(instruction: id, on: &model)
    }
}

public struct SelectShapeCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = Set<ShapeID>

    let previous: Set<ShapeID>
    let next: Set<ShapeID>

    public static func execute(instruction: Set<ShapeID>, on model: inout Document) throws -> (
        doneCommand: SelectShapeCommand, hadEffect: Bool
    ) {
        let prev = model.selected
        model.selected = instruction
        return (SelectShapeCommand(previous: prev, next: instruction), prev != instruction)
    }

    public func undo(on model: inout Document) {
        model.selected = previous
    }

    public func redo(on model: inout Document) {
        model.selected = next
    }
}

public enum CompositePresets {
    // Example: duplicate selected shape and move it, as a transactional composite
    public static func duplicateAndMove(id: ShapeID, offset: Point)
        -> CompositeCommandImpl<Document>.Instruction
    {
        return { model, exec in
            guard let idx = model.indexOfShape(id: id) else { throw VectorError.notFound }
            let original = model.shapes[idx]
            let duplicated: Shape
            switch original {
            case .rect(_, let r): duplicated = .rect(.rect(UUID()), r)
            case .circle(_, let c): duplicated = .circle(.circle(UUID()), c)
            }
            let (addCmd, _) = try exec.execute(
                command: AddShapeCommand.self, instruction: duplicated, on: &model)
            _ = try exec.execute(
                command: MoveShapeCommand.self,
                instruction: .init(id: addCmd.shape.id, offset: offset), on: &model)
            _ = try exec.execute(
                command: SelectShapeCommand.self, instruction: [addCmd.shape.id], on: &model)
        }
    }

    // Convenience wrapper for backward compatibility
    public static func duplicateAndMove(id: ShapeID, dx: Double, dy: Double)
        -> CompositeCommandImpl<Document>.Instruction
    {
        return duplicateAndMove(id: id, offset: Point(x: dx, y: dy))
    }
}

public struct DuplicateAndMoveCommand: Command {
    let compositeCommand: CompositeCommandImpl<Document>

    public static func execute(instruction: (id: ShapeID, offset: Point), on: inout Document) throws
        -> (
            doneCommand: DuplicateAndMoveCommand, hadEffect: Bool
        )
    {
        let (doneCommand, hadEffect) = try CompositeCommandImpl<Document>.execute(
            instruction: { model, exec in
                guard let idx = model.indexOfShape(id: instruction.id) else {
                    throw VectorError.notFound
                }
                let original = model.shapes[idx]
                let duplicated: Shape
                switch original {
                case .rect(_, let r): duplicated = .rect(.rect(UUID()), r)
                case .circle(_, let c): duplicated = .circle(.circle(UUID()), c)
                }
                let (addCmd, _) = try exec.execute(
                    command: AddShapeCommand.self, instruction: duplicated, on: &model)
                _ = try exec.execute(
                    command: MoveShapeCommand.self,
                    instruction: .init(id: addCmd.shape.id, offset: instruction.offset), on: &model)
                _ = try exec.execute(
                    command: SelectShapeCommand.self, instruction: [addCmd.shape.id], on: &model)
            }, on: &on)

        return (DuplicateAndMoveCommand(compositeCommand: doneCommand), hadEffect)
    }

    public func undo(on: inout Document) {
        compositeCommand.undo(on: &on)
    }

    public func redo(on: inout Document) {
        compositeCommand.redo(on: &on)
    }

    public typealias Model = Document
    public typealias Instruction = (id: ShapeID, offset: Point)
}

public struct DuplicateTwice: CompositeCommand {
    public let compositeCommand: CompositeCommandImpl<Document>

    public typealias Model = Document
    public typealias Instruction = ShapeID

    public init(compositeCommand: CompositeCommandImpl<Document>) {
        self.compositeCommand = compositeCommand
    }

    public static func compositeExecute(
        instruction shapeToDuplicate: ShapeID, on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        _ = try executor.execute(
            command: DuplicateAndMoveCommand.self,
            instruction: (id: shapeToDuplicate, offset: Point(x: 40, y: 40)), on: &model)
        _ = try executor.execute(
            command: DuplicateAndMoveCommand.self,
            instruction: (id: shapeToDuplicate, offset: Point(x: -40, y: 40)), on: &model)
    }
}

public struct Triplicate: CompositeActor {
    public static func compositeExecute(
        instruction shapesToTriplicate: Set<ShapeID>, on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        // Store the original selection
        let originalSelection = model.selected
        
        // Triplicate each selected shape
        for shapeID in shapesToTriplicate {
            _ = try executor.execute(
                command: DuplicateAndMoveCommand.self,
                instruction: (id: shapeID, offset: Point(x: 40, y: 40)), on: &model)
            _ = try executor.execute(
                command: DuplicateAndMoveCommand.self,
                instruction: (id: shapeID, offset: Point(x: -40, y: 40)), on: &model)
            _ = try executor.execute(
                command: DuplicateAndMoveCommand.self,
                instruction: (id: shapeID, offset: Point(x: 0, y: -60)), on: &model)
        }
        
        // Restore the original selection
        _ = try executor.execute(
            command: SelectShapeCommand.self, instruction: originalSelection, on: &model)
    }
}
public typealias TriplicateCommand = CompositeCommandFromActor<Triplicate>

// MARK: - Multiselection Commands

public struct SelectAllCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = Void
    
    let previous: Set<ShapeID>
    
    public static func execute(instruction: Void, on model: inout Document) throws -> (
        doneCommand: SelectAllCommand, hadEffect: Bool
    ) {
        let prev = model.selected
        let all = model.allShapeIDs
        model.selected = all
        return (SelectAllCommand(previous: prev), prev != all)
    }
    
    public func undo(on model: inout Document) {
        model.selected = previous
    }
    
    public func redo(on model: inout Document) {
        model.selected = model.allShapeIDs
    }
}

public struct ToggleSelectionCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = ShapeID
    
    let shapeID: ShapeID
    let wasSelected: Bool
    
    public static func execute(instruction: ShapeID, on model: inout Document) throws -> (
        doneCommand: ToggleSelectionCommand, hadEffect: Bool
    ) {
        let wasSelected = model.selected.contains(instruction)
        if wasSelected {
            model.selected.remove(instruction)
        } else {
            model.selected.insert(instruction)
        }
        return (ToggleSelectionCommand(shapeID: instruction, wasSelected: wasSelected), true)
    }
    
    public func undo(on model: inout Document) {
        if wasSelected {
            model.selected.insert(shapeID)
        } else {
            model.selected.remove(shapeID)
        }
    }
    
    public func redo(on model: inout Document) {
        if wasSelected {
            model.selected.remove(shapeID)
        } else {
            model.selected.insert(shapeID)
        }
    }
}

public struct ToggleSelectionAndBringToFront: CompositeActor {
    public static func compositeExecute(
        instruction shapeID: ShapeID, on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        // First bring to front, then toggle selection
        _ = try executor.execute(
            command: BringToFrontCommand.self, instruction: shapeID, on: &model)
        _ = try executor.execute(
            command: ToggleSelectionCommand.self, instruction: shapeID, on: &model)
    }
}
public typealias ToggleSelectionAndBringToFrontCommand = CompositeCommandFromActor<ToggleSelectionAndBringToFront>

public struct RectangularSelectionCommand: Command, Sendable {
    public typealias Model = Document
    public struct Instruction: Sendable {
        public let selectionRect: SelectionRect
        public let mode: SelectionMode
        
        public enum SelectionMode: Sendable {
            case replace  // Normal rectangular selection
            case toggle   // Ctrl+rectangular selection
        }
        
        public init(selectionRect: SelectionRect, mode: SelectionMode) {
            self.selectionRect = selectionRect
            self.mode = mode
        }
    }
    
    let previous: Set<ShapeID>
    let next: Set<ShapeID>
    
    public static func execute(instruction: Instruction, on model: inout Document) throws -> (
        doneCommand: RectangularSelectionCommand, hadEffect: Bool
    ) {
        let prev = model.selected
        let intersecting = model.shapesIntersecting(selectionRect: instruction.selectionRect)
        
        let next: Set<ShapeID>
        switch instruction.mode {
        case .replace:
            next = intersecting
        case .toggle:
            // Toggle each intersecting shape
            next = prev.symmetricDifference(intersecting)
        }
        
        model.selected = next
        return (RectangularSelectionCommand(previous: prev, next: next), prev != next)
    }
    
    public func undo(on model: inout Document) {
        model.selected = previous
    }
    
    public func redo(on model: inout Document) {
        model.selected = next
    }
}

// MARK: - Multi-Shape Movement

public struct MoveMultipleShapes: CompositeActor {
    public static func compositeExecute(
        instruction: (shapes: Set<ShapeID>, offset: Point), on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        // Move each selected shape by the same offset
        for shapeID in instruction.shapes {
            let moveInstruction = MoveShapeCommand.Instruction(id: shapeID, offset: instruction.offset)
            _ = try executor.execute(
                command: MoveShapeCommand.self, instruction: moveInstruction, on: &model)
        }
    }
}
public typealias MoveMultipleShapesCommand = CompositeCommandFromActor<MoveMultipleShapes>

// MARK: - Multi-Shape Duplication and Movement

public struct DuplicateAndMoveMultipleShapes: CompositeActor {
    public static func compositeExecute(
        instruction: (shapes: Set<ShapeID>, offset: Point), on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        var newShapeIDs: Set<ShapeID> = []
        
        // Duplicate each selected shape and move it
        for shapeID in instruction.shapes {
            guard let idx = model.indexOfShape(id: shapeID) else { continue }
            let original = model.shapes[idx]
            
            // Create duplicated shape with new ID
            let duplicated: Shape
            switch original {
            case .rect(_, let r): duplicated = .rect(.rect(UUID()), r)
            case .circle(_, let c): duplicated = .circle(.circle(UUID()), c)
            }
            
            // Add the duplicated shape
            let (addCmd, _) = try executor.execute(
                command: AddShapeCommand.self, instruction: duplicated, on: &model)
            
            // Move the duplicated shape by the offset
            let moveInstruction = MoveShapeCommand.Instruction(id: addCmd.shape.id, offset: instruction.offset)
            _ = try executor.execute(
                command: MoveShapeCommand.self, instruction: moveInstruction, on: &model)
            
            newShapeIDs.insert(addCmd.shape.id)
        }
        
        // Select the newly created shapes
        _ = try executor.execute(
            command: SelectShapeCommand.self, instruction: newShapeIDs, on: &model)
    }
}
public typealias DuplicateAndMoveMultipleShapesCommand = CompositeCommandFromActor<DuplicateAndMoveMultipleShapes>

// MARK: - Multi-Shape Deletion

public struct DeleteMultipleShapes: CompositeActor {
    public static func compositeExecute(
        instruction shapes: Set<ShapeID>, on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        // Delete each selected shape
        for shapeID in shapes {
            _ = try executor.execute(
                command: DeleteShapeCommand.self, instruction: shapeID, on: &model)
        }
    }
}
public typealias DeleteMultipleShapesCommand = CompositeCommandFromActor<DeleteMultipleShapes>

// MARK: - Multi-Shape Color Changes

public struct SetColorMultipleShapes: CompositeActor {
    public static func compositeExecute(
        instruction: (shapes: Set<ShapeID>, color: Color), on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        // Set color for each selected shape
        for shapeID in instruction.shapes {
            let colorInstruction = SetColorCommand.Instruction(id: shapeID, color: instruction.color)
            _ = try executor.execute(
                command: SetColorCommand.self, instruction: colorInstruction, on: &model)
        }
    }
}
public typealias SetColorMultipleShapesCommand = CompositeCommandFromActor<SetColorMultipleShapes>