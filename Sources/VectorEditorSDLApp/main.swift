import Foundation
import SDL
import Undonete
import VectorEditorCore

#if os(Linux)
    // On Linux ensure libsdl2-dev is installed. Runtime assumes system SDL2.
#endif

// UI coordinate type for SDL operations
struct UIPoint: Equatable {
    var x: Int32
    var y: Int32

    init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }

    init(_ x: Int32, _ y: Int32) {
        self.x = x
        self.y = y
    }

    // Convert to model coordinates
    func toModelPoint() -> Point {
        Point(x: Double(x), y: Double(y))
    }

    static func - (lhs: UIPoint, rhs: UIPoint) -> UIPoint {
        UIPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func + (lhs: UIPoint, rhs: UIPoint) -> UIPoint {
        UIPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

// Convert model Point to UI coordinates
extension Point {
    func toUIPoint() -> UIPoint {
        UIPoint(x: Int32(x), y: Int32(y))
    }
}

func sdlAssert(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition { fatalError("SDL Error: \(message()) - \(String(cString: SDL_GetError()))") }
}

// Simple digit rendering for FPS display
func drawDigit(_ renderer: OpaquePointer?, digit: Int, x: Int32, y: Int32, size: Int32 = 2) {
    let patterns: [[String]] = [
        // 0
        [
            "111",
            "101",
            "101",
            "101",
            "111",
        ],
        // 1
        [
            "010",
            "110",
            "010",
            "010",
            "111",
        ],
        // 2
        [
            "111",
            "001",
            "111",
            "100",
            "111",
        ],
        // 3
        [
            "111",
            "001",
            "111",
            "001",
            "111",
        ],
        // 4
        [
            "101",
            "101",
            "111",
            "001",
            "001",
        ],
        // 5
        [
            "111",
            "100",
            "111",
            "001",
            "111",
        ],
        // 6
        [
            "111",
            "100",
            "111",
            "101",
            "111",
        ],
        // 7
        [
            "111",
            "001",
            "001",
            "001",
            "001",
        ],
        // 8
        [
            "111",
            "101",
            "111",
            "101",
            "111",
        ],
        // 9
        [
            "111",
            "101",
            "111",
            "001",
            "111",
        ],
    ]

    if digit < 0 || digit > 9 { return }

    // Set color to white for better visibility on dark background:
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    let pattern = patterns[digit]
    for (row, line) in pattern.enumerated() {
        for (col, char) in line.enumerated() {
            if char == "1" {
                var rect = SDL_Rect(
                    x: x + Int32(col) * size,
                    y: y + Int32(row) * size,
                    w: size,
                    h: size
                )
                SDL_RenderFillRect(renderer, &rect)
            }
        }
    }
}

// Draw a number on screen
func drawNumber(_ renderer: OpaquePointer?, number: Int, x: Int32, y: Int32, size: Int32 = 2) {
    let numberStr = String(number)
    var currentX = x

    for char in numberStr {
        if let digit = Int(String(char)) {
            drawDigit(renderer, digit: digit, x: currentX, y: y, size: size)
            currentX += 4 * size  // Move to next digit position
        }
    }
}

// Main execution
func main() {
    // Initialize SDL
    sdlAssert(SDL_Init(SDL_INIT_VIDEO) == 0, "SDL could not initialize")
    defer { SDL_Quit() }

    let window = SDL_CreateWindow(
        "Undonete Vector Editor",
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        Int32(SDL_WINDOWPOS_CENTERED_MASK),
        800, 600,
        SDL_WINDOW_SHOWN.rawValue
    )
    sdlAssert(window != nil, "Window creation failed")
    defer { if let w = window { SDL_DestroyWindow(w) } }

    let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue)
    sdlAssert(renderer != nil, "Renderer creation failed")
    defer { if let r = renderer { SDL_DestroyRenderer(r) } }

    // Application state
    var document = Document()
    var commandManager = LinearCommandManager<Document>()

    // State for dragging
    var isDragging = false
    var dragTarget: ShapeID? = nil
    var dragStart = UIPoint(0, 0)
    var visualOffset = UIPoint(0, 0)  // Visual offset for UI feedback

    // FPS tracking
    var frameCount: UInt64 = 0
    var lastFPSUpdate = SDL_GetTicks64()
    var currentFPS: Double = 0.0

    // Add some initial shapes with attractive colors
    let rectId = ShapeID.rect(UUID())
    let rect = Shape.rect(
        rectId, Rect(origin: Point(x: 100, y: 100), size: Size(width: 120, height: 80), color: .blue)
    )
    _ = try? commandManager.execute(command: AddShapeCommand.self, instruction: rect, on: &document)

    let circleId = ShapeID.circle(UUID())
    let circle = Shape.circle(
        circleId, Circle(center: Point(x: 300, y: 200), radius: 50, color: .purple))
    _ = try? commandManager.execute(
        command: AddShapeCommand.self, instruction: circle, on: &document)

    var running = true
    while running {
        // Update FPS calculation
        frameCount += 1
        let currentTime = SDL_GetTicks64()
        if currentTime - lastFPSUpdate >= 1000 {  // Update every second
            currentFPS = Double(frameCount) * 1000.0 / Double(currentTime - lastFPSUpdate)
            frameCount = 0
            lastFPSUpdate = currentTime
        }

        // Handle events
        var event = SDL_Event()
        while SDL_PollEvent(&event) != 0 {
            var mouseX: Int32 = 0
            var mouseY: Int32 = 0
            SDL_GetMouseState(&mouseX, &mouseY)

            switch event.type {
            case SDL_QUIT.rawValue:
                running = false

            case SDL_MOUSEBUTTONDOWN.rawValue:
                let mousePoint = UIPoint(x: event.button.x, y: event.button.y)
                let modelPoint = mousePoint.toModelPoint()

                // Find shape under cursor
                if let hitShape = document.hitTest(point: modelPoint) {
                    // Select the shape and bring it to front using single composite command
                    _ = try? commandManager.execute(
                        command: SelectAndBringToFrontCommand.self, instruction: hitShape, on: &document)

                    // Start dragging
                    isDragging = true
                    dragTarget = hitShape
                    dragStart = mousePoint
                    visualOffset = UIPoint(0, 0)
                } else {
                    _ = try? commandManager.execute(
                        command: SelectAndBringToFrontCommand.self, instruction: nil, on: &document)
                }

            case SDL_MOUSEBUTTONUP.rawValue:
                if isDragging, let target = dragTarget {
                    // Apply the actual movement command
                    let moveOffset = visualOffset.toModelPoint()
                    if moveOffset.x != 0 || moveOffset.y != 0 {
                        let moveInstruction = MoveShapeCommand.Instruction(
                            id: target, offset: moveOffset)
                        _ = try? commandManager.execute(
                            command: MoveShapeCommand.self, instruction: moveInstruction,
                            on: &document)
                    }

                    // Reset drag state
                    isDragging = false
                    dragTarget = nil
                    visualOffset = UIPoint(0, 0)
                }

            case SDL_MOUSEMOTION.rawValue:
                if isDragging {
                    let currentMouse = UIPoint(x: event.motion.x, y: event.motion.y)
                    visualOffset = currentMouse - dragStart
                }

            case SDL_KEYDOWN.rawValue:
                switch event.key.keysym.sym {
                case Int32(SDLK_z.rawValue):
                    // Undo with Ctrl+Z
                    if event.key.keysym.mod & UInt16(KMOD_CTRL.rawValue) != 0 {
                        _ = commandManager.undo(on: &document)
                    }
                case Int32(SDLK_y.rawValue):
                    // Redo with Ctrl+Y
                    if event.key.keysym.mod & UInt16(KMOD_CTRL.rawValue) != 0 {
                        _ = commandManager.redo(on: &document)
                    }
                case Int32(SDLK_d.rawValue):
                    // Delete selected shape with Delete key or Ctrl+D
                    if let selected = document.selected {
                        _ = try? commandManager.execute(
                            command: DeleteShapeCommand.self, instruction: selected, on: &document)
                    }
                case Int32(SDLK_r.rawValue):
                    // Add modern blue rectangle
                    let newRectId = ShapeID.rect(UUID())
                    let newRect = Shape.rect(
                        newRectId,
                        Rect(
                            origin: Point(x: Double(mouseX), y: Double(mouseY)),
                            size: Size(width: 80, height: 60),
                            color: .blue))
                    _ = try? commandManager.execute(
                        command: AddShapeCommand.self, instruction: newRect, on: &document)
                case Int32(SDLK_c.rawValue):
                    // Add purple circle
                    let newCircleId = ShapeID.circle(UUID())
                    let newCircle = Shape.circle(
                        newCircleId,
                        Circle(
                            center: Point(x: Double(mouseX), y: Double(mouseY)), radius: 40,
                            color: .purple)
                    )
                    _ = try? commandManager.execute(
                        command: AddShapeCommand.self, instruction: newCircle, on: &document)
                case Int32(SDLK_1.rawValue):
                    // Set selected shape to vibrant red
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .red)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_2.rawValue):
                    // Set selected shape to fresh green
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .green)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_3.rawValue):
                    // Set selected shape to modern blue
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .blue)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_4.rawValue):
                    // Set selected shape to rich purple
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .purple)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_5.rawValue):
                    // Set selected shape to warm orange
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .orange)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_6.rawValue):
                    // Set selected shape to cool teal
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .teal)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_7.rawValue):
                    // Set selected shape to bright pink
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .pink)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_8.rawValue):
                    // Set selected shape to golden amber
                    if let selected = document.selected {
                        let colorInstruction = SetColorCommand.Instruction(
                            id: selected, color: .amber)
                        _ = try? commandManager.execute(
                            command: SetColorCommand.self, instruction: colorInstruction,
                            on: &document)
                    }
                case Int32(SDLK_SPACE.rawValue):
                    // Duplicate and move selected shape (composite command demo)
                    if let selected = document.selected {
                        _ = try? commandManager.execute(
                            command: DuplicateAndMoveCommand.self,
                            instruction: (id: selected, offset: Point(x: 20, y: 20)), on: &document)
                    }

                case Int32(SDLK_s.rawValue):
                    if let selected = document.selected {
                        _ = try? commandManager.execute(
                            command: TriplicateCommand.self, instruction: selected, on: &document)
                    }
                default:
                    break
                }
            default:
                break
            }
        }

        // Clear screen with modern dark background
        sdlAssert(
            SDL_SetRenderDrawColor(renderer, 30, 30, 35, 255) == 0,
            "Failed to set background color")
        sdlAssert(SDL_RenderClear(renderer) == 0, "Failed to clear renderer")

        // Render shapes
        for shape in document.shapes {
            let color: Color
            switch shape {
            case .rect(_, let r): color = r.color
            case .circle(_, let c): color = c.color
            }

            // Apply color with enhanced color mapping
            switch color {
            case .red:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 239, 68, 68, 255) == 0, "Failed to set red color"
                )
            case .green:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 34, 197, 94, 255) == 0,
                    "Failed to set green color")
            case .blue:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 59, 130, 246, 255) == 0,
                    "Failed to set blue color")
            case .purple:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 147, 51, 234, 255) == 0,
                    "Failed to set purple color")
            case .orange:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 249, 115, 22, 255) == 0,
                    "Failed to set orange color")
            case .teal:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 20, 184, 166, 255) == 0,
                    "Failed to set teal color")
            case .pink:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 236, 72, 153, 255) == 0,
                    "Failed to set pink color")
            case .amber:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 245, 158, 11, 255) == 0,
                    "Failed to set amber color")
            case .black:
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) == 0, "Failed to set black color"
                )
            default:
                // For any other color, use the RGB values directly
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a) == 0,
                    "Failed to set color")
            }

            // Calculate visual offset if this shape is being dragged
            let renderOffset = (isDragging && dragTarget == shape.id) ? visualOffset : UIPoint(0, 0)

            switch shape {
            case .rect(_, let r):
                let adjustedOrigin = r.origin.toUIPoint() + renderOffset
                var rect = SDL_Rect(
                    x: adjustedOrigin.x,
                    y: adjustedOrigin.y,
                    w: Int32(r.size.width),
                    h: Int32(r.size.height)
                )
                sdlAssert(SDL_RenderFillRect(renderer, &rect) == 0, "Failed to render rectangle")

            case .circle(_, let c):
                let adjustedCenter = c.center.toUIPoint() + renderOffset
                let cx = adjustedCenter.x
                let cy = adjustedCenter.y
                let radius = Int32(c.radius)

                // Simple filled circle using horizontal lines
                for y in (cy - radius)...(cy + radius) {
                    let dy = y - cy
                    let dx = Int32(sqrt(max(0, Double(radius * radius - dy * dy))))
                    var line = SDL_Rect(x: cx - dx, y: y, w: 2 * dx, h: 1)
                    SDL_RenderFillRect(renderer, &line)
                }
            }

            // Enhanced selection outline with 2px border and glow effect
            if document.selected == shape.id {
                // Create a bright cyan selection outline with glow
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 34, 211, 238, 255) == 0,
                    "Failed to set cyan selection color")
                
                switch shape {
                case .rect(_, let r):
                    let adjustedOrigin = r.origin.toUIPoint() + renderOffset
                    
                    // Draw 2px thick outline by drawing multiple rectangles
                    for thickness in 0..<2 {
                        var outline = SDL_Rect(
                            x: adjustedOrigin.x - 2 - Int32(thickness),
                            y: adjustedOrigin.y - 2 - Int32(thickness),
                            w: Int32(r.size.width) + 4 + Int32(thickness * 2),
                            h: Int32(r.size.height) + 4 + Int32(thickness * 2)
                        )
                        SDL_RenderDrawRect(renderer, &outline)
                    }
                    
                case .circle(_, let c):
                    let adjustedCenter = c.center.toUIPoint() + renderOffset
                    let cx = adjustedCenter.x
                    let cy = adjustedCenter.y
                    
                    // Draw 2px thick circle outline
                    for outlineThickness in 0..<2 {
                        let outerRadius = Int32(c.radius) + 2 + Int32(outlineThickness)
                        
                        // Draw circle outline with more points for smoothness
                        for angle in stride(from: 0, to: 360, by: 1) {
                            let radians = Double(angle) * Double.pi / 180.0
                            let x = cx + Int32(Double(outerRadius) * cos(radians))
                            let y = cy + Int32(Double(outerRadius) * sin(radians))
                            SDL_RenderDrawPoint(renderer, x, y)
                        }
                    }
                }
            }
        }

        // Display FPS in top-left corner with bright text on dark background
        sdlAssert(
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255) == 0, "Failed to set white color")

        // Draw FPS number using simple bitmap approach
        drawNumber(renderer, number: Int(currentFPS), x: 40, y: 10, size: 2)

        // Draw "FPS" label in white
        sdlAssert(SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255) == 0, "Failed to set white color")

        // Simple "F"
        var rect = SDL_Rect(x: 10, y: 10, w: 2, h: 10)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 10, y: 10, w: 6, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 10, y: 14, w: 4, h: 2)
        SDL_RenderFillRect(renderer, &rect)

        // Simple "P"
        rect = SDL_Rect(x: 18, y: 10, w: 2, h: 10)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 18, y: 10, w: 4, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 18, y: 14, w: 4, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 20, y: 12, w: 2, h: 2)
        SDL_RenderFillRect(renderer, &rect)

        // Simple "S"
        rect = SDL_Rect(x: 24, y: 10, w: 4, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 24, y: 12, w: 2, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 24, y: 14, w: 4, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 26, y: 16, w: 2, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 24, y: 18, w: 4, h: 2)
        SDL_RenderFillRect(renderer, &rect)

        // Colon ":"
        rect = SDL_Rect(x: 30, y: 12, w: 2, h: 2)
        SDL_RenderFillRect(renderer, &rect)
        rect = SDL_Rect(x: 30, y: 16, w: 2, h: 2)
        SDL_RenderFillRect(renderer, &rect)

        SDL_RenderPresent(renderer)
        SDL_Delay(1)  // ~60 FPS
    }
}

// Call main function
main()
