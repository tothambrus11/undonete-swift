// The Swift Programming Language
// https://docs.swift.org/swift-book

public enum ExecutionResult<Result> {
    case success(Result, hadEffect: Bool = true)
    case failure(Error)
}

public protocol CommandWithResult<Model> {
    associatedtype Model
    associatedtype Instruction
    associatedtype Result

    static func execute(instruction: Instruction, on model: inout Model) -> ExecutionResult<Result>
    static func undo(instruction: Instruction, on model: inout Model, executionResult: Result)
    static func redo(instruction: Instruction, on model: inout Model, executionResult: Result)
}

public protocol CommandWithoutResult<Model>: CommandWithResult where Result == Void {
    static func execute(instruction: Instruction, on model: inout Model) -> ExecutionResult<Void>
    static func undo(instruction: Instruction, on model: inout Model)
    static func redo(instruction: Instruction, on model: inout Model)
}

extension CommandWithoutResult {
    public static func undo(
        instruction: Instruction, on model: inout Model, executionResult: Result
    ) {
        undo(instruction: instruction, on: &model)
    }

    public static func redo(
        instruction: Instruction, on model: inout Model, executionResult: Result
    ) {
        redo(instruction: instruction, on: &model)
    }
}

public protocol DoneCommand<Model> where Model == Command.Model {
    associatedtype Model
    associatedtype Command: CommandWithResult
    var instruction: Command.Instruction { get }
    var executionResult: Command.Result { get }

    func undo(on model: inout Command.Model)
    func redo(on model: inout Command.Model)
}

public struct ConcreteDoneCommand<C: CommandWithResult>: DoneCommand {
    public typealias Command = C
    public var instruction: C.Instruction
    public var executionResult: C.Result

    public func undo(on model: inout C.Model) {
        Command.undo(instruction: instruction, on: &model, executionResult: executionResult)
    }

    public func redo(on model: inout C.Model) {
        Command.redo(instruction: instruction, on: &model, executionResult: executionResult)
    }
}

struct LinearCommandManager<Model> {
    private var undoStack: [any DoneCommand<Model>]
    private var redoStack: [any DoneCommand<Model>]

    public mutating func execute<Command: CommandWithResult>(
        command: Command, instruction: Command.Instruction, on model: inout Command.Model
    ) -> ExecutionResult<Command.Result> where Command.Model == Model {
        let result = Command.execute(instruction: instruction, on: &model)

        switch result {
        case .failure(_):
            return result
        case .success(let executionResult, let hadEffect):
            if !hadEffect {
                return result
            }

            let doneCommand = ConcreteDoneCommand<Command>(
                instruction: instruction,
                executionResult: executionResult
            )
            undoStack.append(doneCommand)
            redoStack.removeAll()

            return result
        }
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
struct CompositeCommand<M, Instruction>: CommandWithResult {
    static func execute(instruction: (), on model: inout Model) -> ExecutionResult<CompositeCommandState<M>> {
        // there needs to be some state in the execute that isn't captured.
    }

    static func undo(instruction: (), on model: inout Model, executionResult: CompositeCommandState<M>) {
        
    }

    static func redo(instruction: (), on model: inout Model, executionResult: CompositeCommandState<M>) {
        
    }

    typealias Model = M
    typealias Instruction = ()
    typealias Result = CompositeCommandState<M>
    
}