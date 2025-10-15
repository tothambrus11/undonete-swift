import Testing
import Foundation
@testable import VectorEditorCore
import Undonete

struct VectorEditorCoreTests {

    @Test func addMoveDeleteUndoRedo() throws {
        var doc = Document()
        var mgr = LinearCommandManager<Document>()

        let id = ShapeID.rect(UUID())
        let shape = Shape.rect(id, Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10), color: .red))
        let (add, hadEffect) = try AddShapeCommand.execute(instruction: shape, on: &doc, commandManager: &mgr)
        #expect(hadEffect)
        #expect(doc.shapes.count == 1)

        _ = try MoveShapeCommand.execute(instruction: .init(id: add.shape.id, offset: Point(x: 5, y: 3)), on: &doc, commandManager: &mgr)
        if case .rect(_, let r)? = doc.shapes.first { #expect(r.origin.x == 5 && r.origin.y == 3) }

        _ = try DeleteShapeCommand.execute(instruction: add.shape.id, on: &doc, commandManager: &mgr)
        #expect(doc.shapes.isEmpty)

        let u1 = mgr.undo(on: &doc)
        #expect(u1)
        #expect(doc.shapes.count == 1)

        let u2 = mgr.undo(on: &doc)
        #expect(u2)
        if case .rect(_, let r)? = doc.shapes.first { #expect(r.origin.x == 0 && r.origin.y == 0) }

        let u3 = mgr.undo(on: &doc)
        #expect(u3)
        #expect(doc.shapes.isEmpty)

        let r1 = mgr.redo(on: &doc)
        #expect(r1)
        #expect(doc.shapes.count == 1)
    }

    @Test func compositeDuplicateTransactional() throws {
        var doc = Document()
        var mgr = LinearCommandManager<Document>()

        let baseId = ShapeID.circle(UUID())
        let baseShape = Shape.circle(baseId, Circle(center: Point(x: 10, y: 10), radius: 5, color: .blue))
        _ = try AddShapeCommand.execute(instruction: baseShape, on: &doc, commandManager: &mgr)

        // success
        let (_, ok) = try CompositeCommand.execute(instruction: CompositePresets.duplicateAndMove(id: baseId, offset: Point(x: 10, y: 0)), on: &doc, commandManager: &mgr)
        #expect(ok)
        #expect(doc.shapes.count == 2)

        // failure path rollback
        let bogus = ShapeID.rect(UUID())
        do {
            _ = try CompositeCommand.execute(instruction: CompositePresets.duplicateAndMove(id: bogus, offset: Point(x: 10, y: 0)), on: &doc, commandManager: &mgr)
            Issue.record("Expected error for notFound")
        } catch {
            // ensure no shape added
            #expect(doc.shapes.count == 2)
        }
    }
}
