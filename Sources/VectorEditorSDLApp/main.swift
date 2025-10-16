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
    var isDuplicateDragging = false  // Track if Ctrl+drag is active
    var isCtrlPressed = false  // Track if Ctrl was pressed when mouse went down
    var dragStart = UIPoint(0, 0)
    var visualOffset = UIPoint(0, 0)  // Visual offset for UI feedback
    var hasDraggedSignificantly = false  // Track if mouse has moved enough to be considered a drag
    var selectionHandledInMouseDown = false  // Track if we already handled selection in mouse down
    
    // State for rectangular selection
    var isRectangleSelecting = false
    var rectangleSelectionStart = UIPoint(0, 0)
    var rectangleSelectionEnd = UIPoint(0, 0)

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

                // Check if Ctrl is held for toggle selection
                let modState = SDL_GetModState()
                let ctrlHeld = (modState.rawValue & KMOD_CTRL.rawValue) != 0

                // Find shape under cursor
                if let hitShape = document.hitTest(point: modelPoint) {
                    // Store Ctrl state for later use
                    isCtrlPressed = ctrlHeld
                    hasDraggedSignificantly = false
                    selectionHandledInMouseDown = false
                    
                    // Always start dragging when clicking on a shape
                    // We'll decide what to do (toggle selection vs drag) when mouse is released
                    if document.selected.contains(hitShape) {
                        // Shape is already selected, start dragging all selected shapes
                        isDragging = true
                        isDuplicateDragging = ctrlHeld  // Track if this is a duplicate drag
                        dragStart = mousePoint
                        visualOffset = UIPoint(0, 0)
                        // No selection change needed
                    } else {
                        // Shape is not selected
                        if ctrlHeld {
                            // For Ctrl+click on unselected shape, add it to selection and start dragging
                            var newSelection = document.selected
                            newSelection.insert(hitShape)
                            _ = try? commandManager.execute(
                                command: SelectShapeCommand.self, instruction: newSelection, on: &document)
                            _ = try? commandManager.execute(
                                command: BringToFrontCommand.self, instruction: hitShape, on: &document)
                            selectionHandledInMouseDown = true  // Mark that we handled selection
                        } else {
                            // Normal click: select it and bring to front
                            _ = try? commandManager.execute(
                                command: SelectAndBringToFrontCommand.self, instruction: hitShape, on: &document)
                            selectionHandledInMouseDown = true  // Mark that we handled selection
                        }
                        
                        // Start dragging the shape(s)
                        isDragging = true
                        isDuplicateDragging = ctrlHeld  // Track if this is a duplicate drag
                        dragStart = mousePoint
                        visualOffset = UIPoint(0, 0)
                    }
                } else {
                    if ctrlHeld {
                        // Ctrl+click on empty space: start rectangle selection
                        isRectangleSelecting = true
                        rectangleSelectionStart = mousePoint
                        rectangleSelectionEnd = mousePoint
                    } else {
                        // Click on empty space: deselect all
                        _ = try? commandManager.execute(
                            command: SelectShapeCommand.self, instruction: [], on: &document)
                        
                        // Start rectangle selection
                        isRectangleSelecting = true
                        rectangleSelectionStart = mousePoint
                        rectangleSelectionEnd = mousePoint
                    }
                }

            case SDL_MOUSEBUTTONUP.rawValue:
                if isDragging {
                    if hasDraggedSignificantly {
                        // This was a drag operation - apply movement
                        let moveOffset = visualOffset.toModelPoint()
                        if !document.selected.isEmpty {
                            if isDuplicateDragging {
                                // Use the duplicate and move command
                                let instruction = (shapes: document.selected, offset: moveOffset)
                                _ = try? commandManager.execute(
                                    command: DuplicateAndMoveMultipleShapesCommand.self, instruction: instruction,
                                    on: &document)
                            } else {
                                // Use the regular multi-shape move command
                                let instruction = (shapes: document.selected, offset: moveOffset)
                                _ = try? commandManager.execute(
                                    command: MoveMultipleShapesCommand.self, instruction: instruction,
                                    on: &document)
                            }
                        }
                    } else {
                        // This was just a click (no significant drag) - handle Ctrl+click toggle
                        if isCtrlPressed && !selectionHandledInMouseDown {
                            // Only toggle if we didn't already handle selection in mouse down
                            // Find the shape that was clicked (hit test again)
                            let mousePoint = UIPoint(x: event.button.x, y: event.button.y)
                            let modelPoint = mousePoint.toModelPoint()
                            if let hitShape = document.hitTest(point: modelPoint) {
                                // Toggle selection of the clicked shape
                                _ = try? commandManager.execute(
                                    command: ToggleSelectionAndBringToFrontCommand.self, instruction: hitShape, on: &document)
                            }
                        }
                        // For normal clicks (no Ctrl), selection was already handled in mouse down
                    }

                    // Reset drag state
                    isDragging = false
                    isDuplicateDragging = false
                    isCtrlPressed = false
                    hasDraggedSignificantly = false
                    selectionHandledInMouseDown = false
                    visualOffset = UIPoint(0, 0)
                }
                
                if isRectangleSelecting {
                    // Complete rectangle selection
                    let modState = SDL_GetModState()
                    let ctrlHeld = (modState.rawValue & KMOD_CTRL.rawValue) != 0
                    let selectionMode: RectangularSelectionCommand.Instruction.SelectionMode = 
                        ctrlHeld ? .toggle : .replace
                    
                    let selectionRect = SelectionRect(
                        start: rectangleSelectionStart.toModelPoint(),
                        end: rectangleSelectionEnd.toModelPoint()
                    )
                    
                    let instruction = RectangularSelectionCommand.Instruction(
                        selectionRect: selectionRect,
                        mode: selectionMode
                    )
                    
                    _ = try? commandManager.execute(
                        command: RectangularSelectionCommand.self, 
                        instruction: instruction, 
                        on: &document)
                    
                    // Reset rectangle selection state
                    isRectangleSelecting = false
                }

            case SDL_MOUSEMOTION.rawValue:
                if isDragging {
                    let currentMouse = UIPoint(x: event.motion.x, y: event.motion.y)
                    visualOffset = currentMouse - dragStart
                    
                    // Check if we've dragged significantly (more than 3 pixels in any direction)
                    let dragDistance = sqrt(Double(visualOffset.x * visualOffset.x + visualOffset.y * visualOffset.y))
                    if dragDistance > 3.0 {
                        hasDraggedSignificantly = true
                    }
                } else if isRectangleSelecting {
                    rectangleSelectionEnd = UIPoint(x: event.motion.x, y: event.motion.y)
                }

            case SDL_KEYDOWN.rawValue:
                switch event.key.keysym.sym {
                case Int32(SDLK_a.rawValue):
                    // Select all with Ctrl+A
                    if event.key.keysym.mod & UInt16(KMOD_CTRL.rawValue) != 0 {
                        _ = try? commandManager.execute(
                            command: SelectAllCommand.self, instruction: (), on: &document)
                    }
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
                    // Delete selected shapes with Delete key or Ctrl+D
                    if !document.selected.isEmpty {
                        // Delete all selected shapes as a single composite command
                        _ = try? commandManager.execute(
                            command: DeleteMultipleShapesCommand.self, instruction: document.selected, on: &document)
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
                    // Set selected shapes to vibrant red
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.red)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_2.rawValue):
                    // Set selected shapes to fresh green
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.green)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_3.rawValue):
                    // Set selected shapes to modern blue
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.blue)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_4.rawValue):
                    // Set selected shapes to rich purple
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.purple)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_5.rawValue):
                    // Set selected shapes to warm orange
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.orange)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_6.rawValue):
                    // Set selected shapes to cool teal
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.teal)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_7.rawValue):
                    // Set selected shapes to bright pink
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.pink)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_8.rawValue):
                    // Set selected shapes to golden amber
                    if !document.selected.isEmpty {
                        let instruction = (shapes: document.selected, color: Color.amber)
                        _ = try? commandManager.execute(
                            command: SetColorMultipleShapesCommand.self, instruction: instruction, on: &document)
                    }
                case Int32(SDLK_SPACE.rawValue):
                    // Duplicate and move first selected shape (composite command demo)
                    if let firstSelected = document.selected.first {
                        _ = try? commandManager.execute(
                            command: DuplicateAndMoveCommand.self,
                            instruction: (id: firstSelected, offset: Point(x: 20, y: 20)), on: &document)
                    }

                case Int32(SDLK_s.rawValue):
                    if !document.selected.isEmpty {
                        _ = try? commandManager.execute(
                            command: TriplicateCommand.self, instruction: document.selected, on: &document)
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
            let isSelectedShape = document.selected.contains(shape.id)
            let renderOffset = (isDragging && isSelectedShape && !isDuplicateDragging) ? visualOffset : UIPoint(0, 0)

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
            
            // If Ctrl+dragging, also render the duplicated shape preview
            if isDragging && isDuplicateDragging && isSelectedShape {
                // Render duplicate with slightly transparent/different color
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 
                        UInt8(min(255, Int(color.r) + 50)), 
                        UInt8(min(255, Int(color.g) + 50)), 
                        UInt8(min(255, Int(color.b) + 50)), 
                        180) == 0, "Failed to set duplicate color")
                
                switch shape {
                case .rect(_, let r):
                    let duplicateOrigin = r.origin.toUIPoint() + visualOffset
                    var duplicateRect = SDL_Rect(
                        x: duplicateOrigin.x,
                        y: duplicateOrigin.y,
                        w: Int32(r.size.width),
                        h: Int32(r.size.height)
                    )
                    sdlAssert(SDL_RenderFillRect(renderer, &duplicateRect) == 0, "Failed to render duplicate rectangle")

                case .circle(_, let c):
                    let duplicateCenter = c.center.toUIPoint() + visualOffset
                    let cx = duplicateCenter.x
                    let cy = duplicateCenter.y
                    let radius = Int32(c.radius)

                    // Simple filled circle using horizontal lines
                    for y in (cy - radius)...(cy + radius) {
                        let dy = y - cy
                        let dx = Int32(sqrt(max(0, Double(radius * radius - dy * dy))))
                        var line = SDL_Rect(x: cx - dx, y: y, w: 2 * dx, h: 1)
                        SDL_RenderFillRect(renderer, &line)
                    }
                }
            }

            // Enhanced selection outline with 2px border and glow effect
            if document.selected.contains(shape.id) {
                // Create a bright cyan selection outline with glow
                sdlAssert(
                    SDL_SetRenderDrawColor(renderer, 34, 211, 238, 255) == 0,
                    "Failed to set cyan selection color")
                
                // Function to draw selection outline for a shape at given offset
                let drawSelectionOutline = { (offset: UIPoint) in
                    switch shape {
                    case .rect(_, let r):
                        let adjustedOrigin = r.origin.toUIPoint() + offset
                        
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
                        let adjustedCenter = c.center.toUIPoint() + offset
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
                
                // Draw selection outline for original shape
                if isDragging && !isDuplicateDragging {
                    // Normal drag: show outline at offset position
                    drawSelectionOutline(visualOffset)
                } else {
                    // Not dragging or Ctrl+drag: show outline at original position
                    drawSelectionOutline(UIPoint(0, 0))
                }
                
                // If Ctrl+dragging, also draw selection outline for duplicate
                if isDragging && isDuplicateDragging {
                    drawSelectionOutline(visualOffset)
                }
            }
        }

        // Draw rectangular selection if active
        if isRectangleSelecting {
            // Draw selection rectangle with dashed outline
            sdlAssert(
                SDL_SetRenderDrawColor(renderer, 100, 200, 255, 128) == 0,
                "Failed to set selection rectangle color")
            
            let startX = min(rectangleSelectionStart.x, rectangleSelectionEnd.x)
            let startY = min(rectangleSelectionStart.y, rectangleSelectionEnd.y)
            let endX = max(rectangleSelectionStart.x, rectangleSelectionEnd.x)
            let endY = max(rectangleSelectionStart.y, rectangleSelectionEnd.y)
            
            // Draw selection rectangle outline
            var selectionRect = SDL_Rect(
                x: startX,
                y: startY,
                w: endX - startX,
                h: endY - startY
            )
            SDL_RenderDrawRect(renderer, &selectionRect)
            
            // Draw semi-transparent fill by drawing multiple inner rectangles
            sdlAssert(
                SDL_SetRenderDrawColor(renderer, 100, 200, 255, 64) == 0,
                "Failed to set selection fill color")
            
            for i in 1..<3 {
                var innerRect = SDL_Rect(
                    x: startX + Int32(i),
                    y: startY + Int32(i),
                    w: endX - startX - Int32(i * 2),
                    h: endY - startY - Int32(i * 2)
                )
                if innerRect.w > 0 && innerRect.h > 0 {
                    SDL_RenderDrawRect(renderer, &innerRect)
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
