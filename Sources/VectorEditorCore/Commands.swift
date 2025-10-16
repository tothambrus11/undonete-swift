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
            if model.selected == shape.id { model.selected = nil }
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

public struct SelectShapeCommand: Command, Sendable {
    public typealias Model = Document
    public typealias Instruction = ShapeID?

    let previous: ShapeID?
    let next: ShapeID?

    public static func execute(instruction: ShapeID?, on model: inout Document) throws -> (
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
                command: SelectShapeCommand.self, instruction: addCmd.shape.id, on: &model)
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
                    command: SelectShapeCommand.self, instruction: addCmd.shape.id, on: &model)
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
        instruction shapeToDuplicate: ShapeID, on model: inout Document,
        executor: inout CommandExecutor<Document>
    ) throws {
        _ = try executor.execute(
            command: DuplicateAndMoveCommand.self,
            instruction: (id: shapeToDuplicate, offset: Point(x: 40, y: 40)), on: &model)
        _ = try executor.execute(
            command: DuplicateAndMoveCommand.self,
            instruction: (id: shapeToDuplicate, offset: Point(x: -40, y: 40)), on: &model)
        _ = try executor.execute(
            command: DuplicateAndMoveCommand.self,
            instruction: (id: shapeToDuplicate, offset: Point(x: 0, y: -60)), on: &model)
    }
}
public typealias TriplicateCommand = CompositeCommandFromActor<Triplicate>