import Foundation

public struct Point: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    
    public static let zero = Point(x: 0, y: 0)
    
    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    
    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    
    public static func += (lhs: inout Point, rhs: Point) {
        lhs = lhs + rhs
    }
}

public struct Size: Equatable, Codable, Sendable {
    public var width: Double
    public var height: Double
    
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum ShapeID: Hashable, Codable, Sendable {
    case rect(UUID)
    case circle(UUID)

    public var uuid: UUID {
        switch self {
        case .rect(let id): return id
        case .circle(let id): return id
        }
    }
}

public struct Color: Equatable, Codable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public static let black = Color(r: 0, g: 0, b: 0, a: 255)
    public static let white = Color(r: 255, g: 255, b: 255, a: 255)
    
    // Modern, attractive color palette
    public static let red = Color(r: 239, g: 68, b: 68, a: 255)      // Vibrant red
    public static let green = Color(r: 34, g: 197, b: 94, a: 255)    // Fresh green  
    public static let blue = Color(r: 59, g: 130, b: 246, a: 255)    // Modern blue
    public static let purple = Color(r: 147, g: 51, b: 234, a: 255)  // Rich purple
    public static let orange = Color(r: 249, g: 115, b: 22, a: 255)  // Warm orange
    public static let teal = Color(r: 20, g: 184, b: 166, a: 255)    // Cool teal
    public static let pink = Color(r: 236, g: 72, b: 153, a: 255)    // Bright pink
    public static let amber = Color(r: 245, g: 158, b: 11, a: 255)   // Golden amber
}

public struct Rect: Equatable, Codable, Sendable {
    public var origin: Point
    public var size: Size
    public var color: Color

    public init(origin: Point, size: Size, color: Color) {
        self.origin = origin
        self.size = size
        self.color = color
    }
    
    public init(x: Double, y: Double, width: Double, height: Double, color: Color) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
        self.color = color
    }

    public func contains(point: Point) -> Bool {
        return point.x >= origin.x && point.y >= origin.y && 
               point.x <= origin.x + size.width && point.y <= origin.y + size.height
    }
    
    public func intersects(with other: Rect) -> Bool {
        let left1 = origin.x
        let right1 = origin.x + size.width
        let top1 = origin.y
        let bottom1 = origin.y + size.height
        
        let left2 = other.origin.x
        let right2 = other.origin.x + other.size.width
        let top2 = other.origin.y
        let bottom2 = other.origin.y + other.size.height
        
        return !(right1 < left2 || right2 < left1 || bottom1 < top2 || bottom2 < top1)
    }
    
    public func intersects(with circle: Circle) -> Bool {
        // Find the closest point on the rectangle to the circle center
        let closestX = max(origin.x, min(circle.center.x, origin.x + size.width))
        let closestY = max(origin.y, min(circle.center.y, origin.y + size.height))
        
        // Calculate distance between circle center and closest point
        let dx = circle.center.x - closestX
        let dy = circle.center.y - closestY
        let distanceSquared = dx * dx + dy * dy
        
        return distanceSquared <= circle.radius * circle.radius
    }
}

public struct Circle: Equatable, Codable, Sendable {
    public var center: Point
    public var radius: Double
    public var color: Color

    public init(center: Point, radius: Double, color: Color) {
        self.center = center
        self.radius = radius
        self.color = color
    }
    
    public init(x: Double, y: Double, radius: Double, color: Color) {
        self.center = Point(x: x, y: y)
        self.radius = radius
        self.color = color
    }

    public func contains(point: Point) -> Bool {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx*dx + dy*dy <= radius*radius
    }
    
    public func intersects(with rect: Rect) -> Bool {
        return rect.intersects(with: self)
    }
}

public enum Shape: Equatable, Codable, Sendable {
    case rect(ShapeID, Rect)
    case circle(ShapeID, Circle)

    public var id: ShapeID {
        switch self {
        case .rect(let id, _): return id
        case .circle(let id, _): return id
        }
    }
    
    public func intersects(with selectionRect: Rect) -> Bool {
        switch self {
        case .rect(_, let rect):
            return rect.intersects(with: selectionRect)
        case .circle(_, let circle):
            return circle.intersects(with: selectionRect)
        }
    }
}

public struct SelectionRect: Equatable, Sendable {
    public let start: Point
    public let end: Point
    
    public init(start: Point, end: Point) {
        self.start = start
        self.end = end
    }
    
    public var normalizedRect: Rect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxX = max(start.x, end.x)
        let maxY = max(start.y, end.y)
        
        return Rect(
            origin: Point(x: minX, y: minY),
            size: Size(width: maxX - minX, height: maxY - minY),
            color: .black // Color doesn't matter for selection rect
        )
    }
}

public struct Document: Equatable, Codable, Sendable {
    public var shapes: [Shape] = []
    public var selected: Set<ShapeID> = []
    public var maxZIndex: Int = 0  // Track highest z-index

    public init(shapes: [Shape] = [], selected: Set<ShapeID> = []) {
        self.shapes = shapes
        self.selected = selected
        self.maxZIndex = 0
    }
    
    // Convenience property for backward compatibility with single selection
    public var singleSelected: ShapeID? {
        get { selected.count == 1 ? selected.first : nil }
        set {
            if let newValue = newValue {
                selected = [newValue]
            } else {
                selected = []
            }
        }
    }

    public mutating func indexOfShape(id: ShapeID) -> Int? {
        return shapes.firstIndex { $0.id == id }
    }

    public func hitTest(x: Double, y: Double) -> ShapeID? {
        let point = Point(x: x, y: y)
        return hitTest(point: point)
    }
    
    public func hitTest(point: Point) -> ShapeID? {
        // Hit test from topmost (last) to bottom
        for shape in shapes.reversed() {
            switch shape {
            case .rect(let id, let r): if r.contains(point: point) { return id }
            case .circle(let id, let c): if c.contains(point: point) { return id }
            }
        }
        return nil
    }
    
    public func shapesIntersecting(selectionRect: SelectionRect) -> Set<ShapeID> {
        let rect = selectionRect.normalizedRect
        var intersecting: Set<ShapeID> = []
        
        for shape in shapes {
            if shape.intersects(with: rect) {
                intersecting.insert(shape.id)
            }
        }
        
        return intersecting
    }
    
    public var allShapeIDs: Set<ShapeID> {
        Set(shapes.map { $0.id })
    }
}
