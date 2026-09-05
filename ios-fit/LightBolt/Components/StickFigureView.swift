import SwiftUI

/// How much scenery a figure draws. Cards and list rows skip the expensive
/// extras so a scrolling library never drops frames.
enum StickDetail {
    case full
    case compact

    var drawsFloor: Bool { self == .full }
    var drawsSoftShadow: Bool { self == .full }
    var drawsTrail: Bool { self == .full }
}

/// One drawable piece of the figure, still in world space.
private struct StickBone {
    enum Tone {
        case torso
        case girdle
        case limb
        case neck
        case joint
        case head
        case prop
    }

    let a: StickVec3
    let b: StickVec3
    let tone: Tone

    /// Stroke width in world units, so perspective can scale it.
    var width: Double {
        switch tone {
        case .torso: 0.088
        case .girdle: 0.064
        case .limb: 0.056
        case .neck: 0.05
        case .joint: 0.048
        case .head: 0.05
        case .prop: 0.028
        }
    }
}

/// The signature yellow stickman, now with a body that has depth.
///
/// The figure is authored and solved in three dimensions, then run through a
/// perspective camera: near limbs come forward and grow, far limbs recede and
/// dim, and every bone casts a real shadow onto the floor. The phase is
/// supplied by the caller — the countdown owns the clock, the figure only
/// renders it, which is what keeps the movement locked to the timer.
struct StickFigureView: View {
    let move: StickMove
    /// Position inside the current repetition, 0...1.
    let phase: Double
    var isResting: Bool = false
    /// Faint echo of the previous frame — a sense of speed on fast moves.
    var showsTrail: Bool = true
    var detail: StickDetail = .full

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let framing = move.framing
            let camera = move.camera(orbit: phase * 0.55)

            // Perspective can push a pose slightly past its own box, so the fit
            // keeps a little air around the widest keyframe.
            let scale = min(size.width / (framing.width * 1.1), size.height / (framing.height * 1.06))
            let floorY = size.height - max(4, (size.height - framing.height * scale) / 2) - scale * 0.05
            let originX = size.width / 2 - framing.centerX * scale

            func place(_ v: StickVec3) -> (point: CGPoint, depth: Double, magnification: Double) {
                let projected = camera.project(v)
                return (
                    CGPoint(x: originX + projected.point.x * scale, y: floorY - projected.point.y * scale),
                    projected.depth,
                    projected.magnification
                )
            }

            let skeleton = move.skeleton(at: phase)
            let bones = Self.bones(for: skeleton, prop: move.prop)

            if detail.drawsFloor {
                drawFloor(in: &context, framing: framing, place: place)
            }

            drawShadows(in: &context, bones: bones, scale: scale, place: place)

            if showsTrail, detail.drawsTrail, !move.isHold {
                let echo = Self.bones(for: move.skeleton(at: phase - 0.055), prop: .none)
                draw(bones: echo, in: &context, scale: scale, place: place, fade: 0.14)
            }

            draw(bones: bones, in: &context, scale: scale, place: place, fade: 1)
        }
        .opacity(isResting ? 0.4 : 1)
        .animation(.easeOut(duration: 0.3), value: isResting)
        .accessibilityHidden(true)
    }

    // MARK: Assembly

    private static func bones(for s: StickSkeleton, prop: StickProp) -> [StickBone] {
        var bones: [StickBone] = [
            StickBone(a: s.pelvis, b: s.neck, tone: .torso),
            StickBone(a: s.shoulderFar, b: s.shoulderNear, tone: .girdle),
            StickBone(a: s.hipFar, b: s.hipNear, tone: .girdle),
            StickBone(a: s.neck, b: s.head, tone: .neck),

            StickBone(a: s.shoulderFar, b: s.elbowFar, tone: .limb),
            StickBone(a: s.elbowFar, b: s.handFar, tone: .limb),
            StickBone(a: s.hipFar, b: s.kneeFar, tone: .limb),
            StickBone(a: s.kneeFar, b: s.footFar, tone: .limb),

            StickBone(a: s.shoulderNear, b: s.elbowNear, tone: .limb),
            StickBone(a: s.elbowNear, b: s.handNear, tone: .limb),
            StickBone(a: s.hipNear, b: s.kneeNear, tone: .limb),
            StickBone(a: s.kneeNear, b: s.footNear, tone: .limb),

            StickBone(a: s.handNear, b: s.handNear, tone: .joint),
            StickBone(a: s.handFar, b: s.handFar, tone: .joint),
            StickBone(a: s.footNear, b: s.footNear, tone: .joint),
            StickBone(a: s.footFar, b: s.footFar, tone: .joint),
            StickBone(a: s.head, b: s.head, tone: .head)
        ]
        bones.append(contentsOf: propBones(prop))
        return bones
    }

    /// Furniture, built in the same space as the body so it sorts and casts
    /// shadows alongside it.
    private static func propBones(_ prop: StickProp) -> [StickBone] {
        switch prop {
        case .none:
            return []
        case .box:
            let x0 = -0.78, x1 = -0.18, top = 0.46, z0 = -0.34, z1 = 0.34
            let corners = [
                StickVec3(x0, top, z0), StickVec3(x1, top, z0),
                StickVec3(x1, top, z1), StickVec3(x0, top, z1)
            ]
            var bones: [StickBone] = []
            for index in corners.indices {
                bones.append(StickBone(a: corners[index], b: corners[(index + 1) % 4], tone: .prop))
                bones.append(StickBone(a: corners[index], b: StickVec3(corners[index].x, 0, corners[index].z), tone: .prop))
            }
            return bones
        case .wall:
            let x = -0.44
            return [
                StickBone(a: StickVec3(x, 0, -0.42), b: StickVec3(x, 0, 0.42), tone: .prop),
                StickBone(a: StickVec3(x, 1.72, -0.42), b: StickVec3(x, 1.72, 0.42), tone: .prop),
                StickBone(a: StickVec3(x, 0, -0.42), b: StickVec3(x, 1.72, -0.42), tone: .prop),
                StickBone(a: StickVec3(x, 0, 0.42), b: StickVec3(x, 1.72, 0.42), tone: .prop)
            ]
        case .bar:
            return [
                StickBone(a: StickVec3(0.62, 1.20, -0.36), b: StickVec3(0.62, 1.20, 0.36), tone: .prop)
            ]
        }
    }

    // MARK: Drawing

    private var tint: Color { LightBoltTheme.volt }

    /// A faint ground plane. Without it the perspective has nothing to sit on.
    private func drawFloor(
        in context: inout GraphicsContext,
        framing: StickFraming,
        place: (StickVec3) -> (point: CGPoint, depth: Double, magnification: Double)
    ) {
        let near = 1.05
        let minX = framing.minX
        let maxX = framing.maxX

        var grid = Path()
        for step in 0...5 {
            let z = -near + (2 * near) * Double(step) / 5
            grid.move(to: place(StickVec3(minX, 0, z)).point)
            grid.addLine(to: place(StickVec3(maxX, 0, z)).point)
        }
        for step in 0...6 {
            let x = minX + (maxX - minX) * Double(step) / 6
            grid.move(to: place(StickVec3(x, 0, -near)).point)
            grid.addLine(to: place(StickVec3(x, 0, near)).point)
        }
        context.stroke(grid, with: .color(tint.opacity(0.07)), lineWidth: 1)

        var horizon = Path()
        horizon.move(to: place(StickVec3(minX, 0, near)).point)
        horizon.addLine(to: place(StickVec3(maxX, 0, near)).point)
        context.stroke(horizon, with: .color(tint.opacity(0.24)), lineWidth: 1.5)
    }

    /// Every bone flattened onto the floor along the light direction.
    private func drawShadows(
        in context: inout GraphicsContext,
        bones: [StickBone],
        scale: CGFloat,
        place: (StickVec3) -> (point: CGPoint, depth: Double, magnification: Double)
    ) {
        func paint(_ target: inout GraphicsContext) {
            for bone in bones {
                let lift = max(bone.a.y, bone.b.y)
                let opacity = 0.34 / (1 + lift * 1.05)
                guard opacity > 0.02 else { continue }

                let a = place(StickCamera.shadow(of: bone.a)).point
                let b = place(StickCamera.shadow(of: bone.b)).point
                let width = max(1.2, bone.width * scale * (bone.tone == .head ? 2.4 : 1.15))

                var path = Path()
                if bone.tone == .head || bone.tone == .joint {
                    let radius = width / 2
                    path.addEllipse(in: CGRect(x: a.x - radius, y: a.y - radius * 0.4,
                                               width: radius * 2, height: radius * 0.8))
                    target.fill(path, with: .color(.black.opacity(opacity)))
                    continue
                }
                path.move(to: a)
                path.addLine(to: b)
                target.stroke(
                    path,
                    with: .color(.black.opacity(opacity)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
            }
        }

        if detail.drawsSoftShadow {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: max(1, scale * 0.03)))
                paint(&layer)
            }
        } else {
            paint(&context)
        }
    }

    private func draw(
        bones: [StickBone],
        in context: inout GraphicsContext,
        scale: CGFloat,
        place: (StickVec3) -> (point: CGPoint, depth: Double, magnification: Double),
        fade: Double
    ) {
        // Farthest first, so near limbs genuinely overlap the ones behind them.
        let projected = bones.map { bone -> (bone: StickBone, a: CGPoint, b: CGPoint, depth: Double, magnification: Double) in
            let a = place(bone.a)
            let b = place(bone.b)
            return (bone, a.point, b.point, (a.depth + b.depth) / 2, (a.magnification + b.magnification) / 2)
        }
        .sorted { $0.depth < $1.depth }

        for item in projected {
            let shade = Self.shade(for: item.depth) * fade
            let width = max(0.8, item.bone.width * scale * item.magnification)

            switch item.bone.tone {
            case .head:
                let radius = StickBody.headRadius * scale * item.magnification
                let rect = CGRect(x: item.a.x - radius, y: item.a.y - radius,
                                  width: radius * 2, height: radius * 2)
                if fade > 0.5 {
                    context.fill(
                        Circle().path(in: rect.insetBy(dx: -radius * 0.32, dy: -radius * 0.32)),
                        with: .color(tint.opacity(0.13 * fade))
                    )
                }
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(shade)))

            case .joint:
                let radius = item.bone.width * scale * item.magnification * 0.5
                let rect = CGRect(x: item.a.x - radius, y: item.a.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Circle().path(in: rect), with: .color(tint.opacity(shade)))

            case .prop:
                var path = Path()
                path.move(to: item.a)
                path.addLine(to: item.b)
                context.stroke(
                    path,
                    with: .color(tint.opacity(0.3 * fade)),
                    style: StrokeStyle(lineWidth: max(1, width), lineCap: .round)
                )

            default:
                var path = Path()
                path.move(to: item.a)
                path.addLine(to: item.b)
                context.stroke(
                    path,
                    with: .color(tint.opacity(shade)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    /// Depth cue: the further a bone sits from the camera, the dimmer it reads.
    private static func shade(for depth: Double) -> Double {
        let t = min(1, max(0, (depth + 0.42) / 0.84))
        return 0.5 + 0.5 * t
    }
}

/// Small looping stickman used in lists and cards, driven by its own clock.
struct StickFigureLoop: View {
    let move: StickMove
    var speed: Double = 1

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate * speed
            StickFigureView(
                move: move,
                phase: seconds.truncatingRemainder(dividingBy: move.cycleSeconds) / move.cycleSeconds,
                showsTrail: false,
                detail: .compact
            )
        }
    }
}
