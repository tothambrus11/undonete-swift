public protocol Command<Model> {
    associatedtype Model
    associatedtype Instruction

    /// Executes the command for the first time, capturing any necessary state to allow reproducible undo/redo.
    static func execute(instruction: Instruction, on: inout Model) throws -> (
        doneCommand: Self, hadEffect: Bool
    )

    /// Undoes the command.
    func undo(on: inout Model)

    /// Redoes the command.
    func redo(on: inout Model)
}

extension Command where Instruction == Void {
    /// Convenience initializer for a commands that doesn't depend on an instruction.
    public static func execute(on model: inout Model) throws -> (Self, hadEffect: Bool) {
        return try self.execute(instruction: (), on: &model)
    }
}

struct LinearCommandManager<Model> {
    private var undoStack: [any Command<Model>]
    private var redoStack: [any Command<Model>]

    public mutating func execute<C: Command>(
        command: C.Type, instruction: C.Instruction, on model: inout C.Model
    ) throws -> (doneCommand: C, hadEffect: Bool) where C.Model == Model {
        let result = try C.execute(instruction: instruction, on: &model)

        if result.hadEffect {
            undoStack.append(result.doneCommand)
            redoStack.removeAll()
        }

        return result
    }

    public mutating func undo(on model: inout Model) -> Bool {
        guard let doneCommand = undoStack.popLast() else {
            return false
        }

        doneCommand.undo(on: &model)
        redoStack.append(doneCommand)
        return true
    }

    public mutating func redo(on model: inout Model) -> Bool {
        guard let doneCommand = redoStack.popLast() else {
            return false
        }

        doneCommand.redo(on: &model)
        undoStack.append(doneCommand)
        return true
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public var undoCount: Int {
        undoStack.count
    }

    public var redoCount: Int {
        redoStack.count
    }
}

struct CompositeCommandState<Model> {
    var undoStack: [any DoneCommand<Model>] = []
}
struct CompositeCommand<M, Instruction>: Command {
    static func execute(instruction: (), on model: inout Model) -> ExecutionResult<
        CompositeCommandState<M>
    > {
        // there needs to be some state in the execute that isn't captured.
    }

    static func undo(
        instruction: (), on model: inout Model, executionResult: CompositeCommandState<M>
    ) {

    }

    static func redo(
        instruction: (), on model: inout Model, executionResult: CompositeCommandState<M>
    ) {

    }

    typealias Model = M
    typealias Instruction = ()
    typealias Result = CompositeCommandState<M>

}
