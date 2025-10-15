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

struct AddRectangleCommand: Command {
    let rectangleToInsert: Rectangle

    static func execute(instruction: Rectangle, on model: inout PaintModel) throws -> (
        doneCommand: AddRectangleCommand, hadEffect: Bool
    ) {
        let cmd = AddRectangleCommand(rectangleToInsert: instruction)
        cmd.redo(on: &model)
        return (cmd, true)
    }

    func undo(on model: inout PaintModel) {
        model.rectangles.removeLast()
    }

    func redo(on model: inout PaintModel) {
        model.rectangles.append(rectangleToInsert)
    }
}

struct AddCircleCommand: Command {
    let circleToInsert: Circle
    let insertedAtIndex: Int

    static func execute(instruction: Circle, on model: inout PaintModel) throws -> (
        doneCommand: AddCircleCommand, hadEffect: Bool
    ) {
        model.circles.append(instruction)
        let cmd = AddCircleCommand(
            circleToInsert: instruction, insertedAtIndex: model.circles.count - 1)
        return (cmd, true)
    }

    func undo(on model: inout PaintModel) {
        model.circles.remove(at: insertedAtIndex)
    }

    func redo(on model: inout PaintModel) {
        model.circles.insert(circleToInsert, at: insertedAtIndex)
    }
}

@Test func example() async throws {
    var model = PaintModel()
    var commandExecutor = LinearCommandManager<PaintModel>()

    let res = try AddCircleCommand.execute(
        instruction: Circle(x: 10, y: 20, radius: 5), on: &model, commandManager: &commandExecutor)
    print(res)

    _ = try CompositeCommand.execute(
        instruction: { (model, executor) in

            _ = try executor.execute(
                command: AddRectangleCommand.self,
                instruction: Rectangle(x: 0, y: 0, width: 100, height: 50), on: &model)

            _ = try executor.execute(
                command: AddCircleCommand.self, instruction: Circle(x: 50, y: 50, radius: 25),
                on: &model)

        }, on: &model, commandManager: &commandExecutor)
}
