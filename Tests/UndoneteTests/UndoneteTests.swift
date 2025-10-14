import Testing
@testable import Undonete

struct Rectangle {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct Circle {
    var x: Double
    var y: Double
    var radius: Double
}

struct PaintModel {
    var rectangles: [Rectangle] = []
    var circles: [Circle] = []

    var color: String = "black"
}

struct AddRectangleCommand: CommandWithResult {
    typealias Model = PaintModel
    typealias Instruction = Rectangle
    typealias Result = Int // index of the added rectangle

    func execute(instruction: Rectangle, on model: inout PaintModel) -> ExecutionResult<Int> {
        model.rectangles.append(instruction)
        return .success(model.rectangles.count - 1)
    }

    func undo(instruction: Rectangle, on model: inout PaintModel, executionResult: Int) {
        model.rectangles.remove(at: executionResult)
    }

    func redo(instruction rectangleToInsert: Rectangle, on model: inout PaintModel, executionResult insertionIndex: Int) {
        model.rectangles.insert(rectangleToInsert, at: insertionIndex)
    }

    static let command = AddRectangleCommand()
}

struct AddCircleCommand: CommandWithoutResult {
    typealias Model = PaintModel
    typealias Instruction = Circle

    func execute(instruction: Circle, on model: inout PaintModel) -> ExecutionResult<Void> {
        model.circles.append(instruction)
        return .success(())
    }

    func undo(instruction: Circle, on model: inout PaintModel) {
        model.circles.removeLast()
    }

    func redo(instruction: Circle, on model: inout PaintModel) {
        model.circles.append(instruction)
    }

    static let command = AddCircleCommand()
}

@Test func example() async throws {
    
}
