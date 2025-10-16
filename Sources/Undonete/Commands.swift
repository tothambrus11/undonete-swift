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

public protocol CommandManager<Model> {
    associatedtype Model
    mutating func execute<C: Command>(
        command: C.Type, instruction: C.Instruction, on model: inout C.Model
    ) throws -> (doneCommand: C, hadEffect: Bool) where C.Model == Model
}

extension Command {
    public static func execute<CM: CommandManager<Model>>(
        instruction: Instruction, on model: inout Model, commandManager: inout CM
    ) throws -> (
        doneCommand: Self, hadEffect: Bool
    ) {
        return try commandManager.execute(command: Self.self, instruction: instruction, on: &model)
    }
}

extension Command where Instruction == Void {
    /// Convenience initializer for a commands that doesn't depend on an instruction.
    public static func execute<CM: CommandManager<Model>>(
        on model: inout Model, commandManager: inout CM
    ) throws -> (Self, hadEffect: Bool) where CM.Model == Model {
        return try commandManager.execute(command: Self.self, instruction: (), on: &model)
    }

    /// Convenience initializer for a commands that doesn't depend on an instruction.
    public static func execute(on model: inout Model) throws -> (Self, hadEffect: Bool) {
        return try self.execute(instruction: (), on: &model)
    }
}

public struct LinearCommandManager<Model>: CommandManager {
    private var undoStack: [any Command<Model>] = []
    private var redoStack: [any Command<Model>] = []

    public init() {}

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

public struct CommandExecutor<Model> {
    private var undoStack: [any Command<Model>] = []

    public mutating func execute<C: Command<Model>>(
        command: C.Type, instruction: C.Instruction, on model: inout Model
    ) throws -> (doneCommand: C, hadEffect: Bool) {
        let result = try C.execute(instruction: instruction, on: &model)
        if result.hadEffect {
            undoStack.append(result.doneCommand)
        }
        return result
    }

    fileprivate init() {}
    fileprivate mutating func extractUndoStack() -> [any Command<Model>] {
        var stack: [any Command<Model>] = []
        swap(&stack, &undoStack)
        return stack
    }

    fileprivate mutating func undoAll(on model: inout Model) {
        for command in undoStack.reversed() {
            command.undo(on: &model)
        }
        undoStack.removeAll()
    }
}
public struct CompositeCommandImpl<M>: Command {
    public typealias Model = M
    public typealias CompositeResult = Void  // todo maybe add the possibility for results that are not saved in the command - when becomes necessary.
    public typealias Instruction = (inout Model, inout CommandExecutor<Model>) throws ->
        CompositeResult

    private let undoStack: [any Command<Model>]

    private init(undoStack: [any Command<Model>]) {
        self.undoStack = undoStack
    }

    public static func execute(instruction: Instruction, on model: inout Model) throws -> (
        doneCommand: Self, hadEffect: Bool
    ) {
        var commandExecutor = CommandExecutor<Model>()

        do {
            try instruction(&model, &commandExecutor)
            let undoStack = commandExecutor.extractUndoStack()

            return (
                doneCommand: CompositeCommandImpl(undoStack: undoStack),
                hadEffect: !undoStack.isEmpty
            )
        } catch {
            commandExecutor.undoAll(on: &model)
            throw error
        }
    }

    public func undo(on model: inout Model) {
        // Undo all subcommands in reverse order
        for command in undoStack.reversed() {
            command.undo(on: &model)
        }
    }

    public func redo(on model: inout Model) {
        // Redo all subcommands in order
        for command in undoStack {
            command.redo(on: &model)
        }
    }

}



public protocol CompositeCommand: Command {
    var compositeCommand: CompositeCommandImpl<Model> { get }
    init(compositeCommand: CompositeCommandImpl<Model>)

    static func compositeExecute(
        instruction: Instruction, on model: inout Model, executor: inout CommandExecutor<Model>)
        throws
}

extension CompositeCommand {
    public static func execute(instruction: Instruction, on model: inout Model) throws -> (
        doneCommand: Self, hadEffect: Bool
    ) {
        let (doneCommand, hadEffect) = try CompositeCommandImpl<Model>.execute(
            instruction: { model, exec in
                try compositeExecute(instruction: instruction, on: &model, executor: &exec)
            }, on: &model)

        return (Self(compositeCommand: doneCommand), hadEffect)
    }

    public func undo(on model: inout Model) {
        compositeCommand.undo(on: &model)
    }

    public func redo(on model: inout Model) {
        compositeCommand.redo(on: &model)
    }
}
