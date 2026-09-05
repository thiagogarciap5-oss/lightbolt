import CoreGraphics
import Foundation

// MARK: - Vector

/// A point in the stickman's world.
///
/// `x` grows to the right, `y` grows up, `z` grows toward the camera, and the
/// floor is the plane `y == 0`. A standing figure is about 1.7 units tall.
nonisolated struct StickVec3: Sendable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    init(_ x: Double, _ y: Double, _ z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    static let zero = StickVec3(0, 0, 0)

    static func + (a: StickVec3, b: StickVec3) -> StickVec3 {
        StickVec3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    static func - (a: StickVec3, b: StickVec3) -> StickVec3 {
        StickVec3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    static func * (v: StickVec3, s: Double) -> StickVec3 {
        StickVec3(v.x * s, v.y * s, v.z * s)
    }

    var length: Double { (x * x + y * y + z * z).squareRoot() }

    var normalized: StickVec3 {
        let l = length
        guard l > 0.0001 else { return StickVec3(0, 1, 0) }
        return self * (1 / l)
    }

    func dot(_ o: StickVec3) -> Double { x * o.x + y * o.y + z * o.z }

    /// Rotation about the vertical axis — how the torso twists.
    func rotatedY(degrees: Double) -> StickVec3 {
        guard degrees != 0 else { return self }
        let a = degrees * .pi / 180
        let c = cos(a)
        let s = sin(a)
        return StickVec3(x * c + z * s, y, -x * s + z * c)
    }

    static func lerp(_ a: StickVec3, _ b: StickVec3, _ t: Double) -> StickVec3 {
        StickVec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
    }
}

// MARK: - Pose

/// Which way a joint folds.
///
/// Naming the direction instead of storing a raw sign is what stops knees from
/// silently inverting: `.forward` always means "the knee leads the way the body
/// is facing", whichever camera the move is shot from.
nonisolated enum StickBend: Sendable, Equatable {
    case forward
    case back
    case up
    case down
    case outward
    case inward

    nonisolated func direction(_ facing: StickFacing) -> StickVec3 {
        switch self {
        case .forward: facing.forwardAxis
        case .back: facing.forwardAxis * -1
        case .up: StickVec3(0, 1, 0)
        case .down: StickVec3(0, -1, 0)
        case .outward: facing.lateralAxis
        case .inward: facing.lateralAxis * -1
        }
    }
}

/// Which way the figure is turned relative to the camera.
nonisolated enum StickFacing: Sendable {
    /// Shot from the side; the figure faces `+x`. Push-ups, squats, sit-ups.
    case sagittal
    /// Shot head-on; the figure faces the camera. Jumping jacks, boxing.
    case frontal

    /// Shoulder and hip width run along this axis.
    nonisolated var lateralAxis: StickVec3 {
        switch self {
        case .sagittal: StickVec3(0, 0, 1)
        case .frontal: StickVec3(1, 0, 0)
        }
    }

    /// The way the chest points.
    nonisolated var forwardAxis: StickVec3 {
        switch self {
        case .sagittal: StickVec3(1, 0, 0)
        case .frontal: StickVec3(0, 0, 1)
        }
    }

    /// How far the near limbs sit in front of the far limbs, in depth.
    nonisolated var limbDepth: Double {
        switch self {
        case .sagittal: 0.15
        case .frontal: 0.05
        }
    }

    /// Camera swing, so a move is never seen dead flat.
    nonisolated var yaw: Double {
        switch self {
        case .sagittal: -0.30
        case .frontal: 0.26
        }
    }
}

/// A single frame of the LightBolt stickman.
///
/// Poses are authored by placing only the parts that matter — pelvis, hands and
/// feet — and letting inverse kinematics solve the elbows and knees. That keeps
/// hands and feet planted exactly where they belong instead of drifting through
/// the floor, which is what makes the movement read as a real push-up rather
/// than a wobbling stick.
nonisolated struct StickPose: Sendable, Equatable {
    /// Hip joint — the root of the whole skeleton.
    var pelvis: StickVec3
    /// Absolute spine angle in degrees. 90 = standing upright, 0 = lying flat
    /// with the head to the right.
    var spine: Double
    /// Extra head tilt on top of the spine angle.
    var headTilt: Double = 0
    /// Rotation of the shoulder line about the vertical axis — the part of a
    /// twist a flat drawing can never show.
    var twist: Double = 0
    /// Target for the near (camera-side) hand.
    var handNear: StickVec3
    /// Target for the far hand. Defaults to the near hand.
    var handFar: StickVec3?
    var footNear: StickVec3
    var footFar: StickVec3?
    var elbowBend: StickBend = .back
    var kneeBend: StickBend = .forward

    nonisolated static func lerp(_ a: StickPose, _ b: StickPose, _ t: Double) -> StickPose {
        StickPose(
            pelvis: .lerp(a.pelvis, b.pelvis, t),
            spine: a.spine + (b.spine - a.spine) * t,
            headTilt: a.headTilt + (b.headTilt - a.headTilt) * t,
            twist: a.twist + (b.twist - a.twist) * t,
            handNear: .lerp(a.handNear, b.handNear, t),
            handFar: .lerp(a.handFar ?? a.handNear, b.handFar ?? b.handNear, t),
            footNear: .lerp(a.footNear, b.footNear, t),
            footFar: .lerp(a.footFar ?? a.footNear, b.footFar ?? b.footNear, t),
            elbowBend: t < 0.5 ? a.elbowBend : b.elbowBend,
            kneeBend: t < 0.5 ? a.kneeBend : b.kneeBend
        )
    }
}

/// Every joint of one solved frame, ready to stroke.
nonisolated struct StickSkeleton: Sendable {
    let head: StickVec3
    let headRadius: Double
    let neck: StickVec3
    let pelvis: StickVec3
    let shoulderNear: StickVec3
    let shoulderFar: StickVec3
    let hipNear: StickVec3
    let hipFar: StickVec3
    let elbowNear: StickVec3
    let handNear: StickVec3
    let elbowFar: StickVec3
    let handFar: StickVec3
    let kneeNear: StickVec3
    let footNear: StickVec3
    let kneeFar: StickVec3
    let footFar: StickVec3
}

/// Fixed limb lengths — the proportions of the mascot.
nonisolated enum StickBody {
    nonisolated static let spineLength: Double = 0.54
    nonisolated static let neckToHead: Double = 0.16
    nonisolated static let headRadius: Double = 0.135
    nonisolated static let upperArm: Double = 0.34
    nonisolated static let foreArm: Double = 0.31
    nonisolated static let thigh: Double = 0.46
    nonisolated static let shin: Double = 0.43
    nonisolated static let shoulderHalfWidth: Double = 0.15
    nonisolated static let hipHalfWidth: Double = 0.10
    /// Pelvis height when standing tall.
    nonisolated static let standingHip: Double = 0.88

    nonisolated static var armReach: Double { upperArm + foreArm }
    nonisolated static var legReach: Double { thigh + shin }

    /// Pulls an out-of-range target back onto the limb's own reach.
    ///
    /// Without this a hand authored too far from its shoulder stretches the
    /// forearm like elastic, which is what made several exercises look wrong.
    nonisolated static func reachable(from root: StickVec3, to target: StickVec3, limit: Double) -> StickVec3 {
        let d = target - root
        let l = d.length
        guard l > limit, l > 0.0001 else { return target }
        return root + d * (limit / l)
    }

    /// Two-bone IK in three dimensions.
    ///
    /// `hint` is the way the middle joint should break; it is projected onto the
    /// plane perpendicular to the limb so the elbow or knee always ends up on
    /// the correct side, whatever angle the limb is at.
    nonisolated static func joint(
        from root: StickVec3,
        to target: StickVec3,
        l1: Double,
        l2: Double,
        hint: StickVec3
    ) -> StickVec3 {
        let d = target - root
        let reach = max(0.0001, d.length)
        let u = d * (1 / reach)
        let distance = min(reach, l1 + l2 - 0.0001)

        var perpendicular = hint - u * hint.dot(u)
        if perpendicular.length < 0.001 {
            let up = StickVec3(0, 1, 0)
            perpendicular = up - u * up.dot(u)
        }
        if perpendicular.length < 0.001 {
            let depth = StickVec3(0, 0, 1)
            perpendicular = depth - u * depth.dot(u)
        }

        let along = (distance * distance + l1 * l1 - l2 * l2) / (2 * distance)
        let lift = max(0, l1 * l1 - along * along).squareRoot()
        return root + u * along + perpendicular.normalized * lift
    }

    /// Solves a pose into drawable joints.
    nonisolated static func solve(_ pose: StickPose, facing: StickFacing) -> StickSkeleton {
        let spineRadians = pose.spine * .pi / 180
        let neck = pose.pelvis + StickVec3(cos(spineRadians) * spineLength, sin(spineRadians) * spineLength, 0)
        let headRadians = (pose.spine + pose.headTilt) * .pi / 180
        let head = neck + StickVec3(cos(headRadians) * neckToHead, sin(headRadians) * neckToHead, 0)

        let shoulderAxis = facing.lateralAxis.rotatedY(degrees: pose.twist)
        let shoulderNear = neck + shoulderAxis * shoulderHalfWidth
        let shoulderFar = neck - shoulderAxis * shoulderHalfWidth
        let hipNear = pose.pelvis + facing.lateralAxis * hipHalfWidth
        let hipFar = pose.pelvis - facing.lateralAxis * hipHalfWidth

        // Near limbs sit closer to the camera than far limbs, so a side-on move
        // reads as a body with width rather than a single flat line.
        let depth = StickVec3(0, 0, facing.limbDepth)
        let handNear = reachable(from: shoulderNear, to: pose.handNear + depth, limit: armReach)
        let handFar = reachable(from: shoulderFar, to: (pose.handFar ?? pose.handNear) - depth, limit: armReach)
        let footNear = reachable(from: hipNear, to: pose.footNear + depth, limit: legReach)
        let footFar = reachable(from: hipFar, to: (pose.footFar ?? pose.footNear) - depth, limit: legReach)

        let elbowHint = pose.elbowBend.direction(facing)
        let kneeHint = pose.kneeBend.direction(facing)

        return StickSkeleton(
            head: head,
            headRadius: headRadius,
            neck: neck,
            pelvis: pose.pelvis,
            shoulderNear: shoulderNear,
            shoulderFar: shoulderFar,
            hipNear: hipNear,
            hipFar: hipFar,
            elbowNear: joint(from: shoulderNear, to: handNear, l1: upperArm, l2: foreArm, hint: elbowHint),
            handNear: handNear,
            elbowFar: joint(from: shoulderFar, to: handFar, l1: upperArm, l2: foreArm, hint: elbowHint),
            handFar: handFar,
            kneeNear: joint(from: hipNear, to: footNear, l1: thigh, l2: shin, hint: kneeHint),
            footNear: footNear,
            kneeFar: joint(from: hipFar, to: footFar, l1: thigh, l2: shin, hint: kneeHint),
            footFar: footFar
        )
    }
}

// MARK: - Camera

/// One projected joint: where to draw it, and how near the camera it is.
nonisolated struct StickProjection: Sendable {
    let point: CGPoint
    /// Positive is closer to the camera. Used for sorting and shading.
    let depth: Double
    /// Perspective magnification at this depth.
    let magnification: Double
}

/// A simple orbiting camera with a real perspective divide.
nonisolated struct StickCamera: Sendable {
    var yaw: Double
    var pitch: Double
    /// Distance to the lens. Larger is a flatter, more telephoto look.
    var lens: Double = 7.0
    /// Height the perspective pivots around, so the figure isn't distorted.
    var pivot: Double = 0.85

    nonisolated func project(_ v: StickVec3) -> StickProjection {
        let cy = cos(yaw)
        let sy = sin(yaw)
        let x1 = v.x * cy + v.z * sy
        let z1 = -v.x * sy + v.z * cy

        let cp = cos(pitch)
        let sp = sin(pitch)
        let yRelative = v.y - pivot
        let y1 = yRelative * cp - z1 * sp
        let depth = yRelative * sp + z1 * cp

        let magnification = lens / max(1.2, lens - depth)
        return StickProjection(
            point: CGPoint(x: x1 * magnification, y: pivot + y1 * magnification),
            depth: depth,
            magnification: magnification
        )
    }

    /// Where a point's shadow lands on the floor, for a light up and behind.
    nonisolated static func shadow(of v: StickVec3) -> StickVec3 {
        StickVec3(v.x - v.y * 0.32, 0.004, v.z - v.y * 0.20)
    }
}

// MARK: - Move catalogue

/// Every movement the stickman knows how to perform.
///
/// One case per distinct movement pattern; exercises that share a pattern (a
/// diamond push-up is still a push-up) share the animation and explain the
/// variation in their coaching cue.
nonisolated enum StickMove: String, CaseIterable, Sendable, Codable {
    case pushUp
    case pikePushUp
    case shoulderTap
    case plank
    case plankJack
    case sidePlank
    case mountainClimber
    case burpee
    case squatThrust
    case bearHold
    case inchworm
    case jumpingJack
    case starJump
    case highKnees
    case buttKick
    case skater
    case jumpRope
    case shadowBox
    case squat
    case jumpSquat
    case squatPulse
    case wallSit
    case lunge
    case splitSquat
    case gluteBridge
    case bridgeMarch
    case donkeyKick
    case calfRaise
    case crunch
    case sitUp
    case bicycleCrunch
    case legRaise
    case flutterKick
    case hollowHold
    case russianTwist
    case superman
    case birdDog
    case deadBug
    case chairDip
    case doorRow
    case toeTouch
    case armCircle

    /// Natural time for one repetition, in seconds. The runner stretches this
    /// slightly so a set always ends on a completed rep.
    nonisolated var cycleSeconds: Double {
        switch self {
        case .pushUp, .pikePushUp, .sitUp, .chairDip, .doorRow, .squat, .lunge, .splitSquat: 2.4
        case .burpee, .inchworm, .squatThrust: 3.4
        case .crunch, .legRaise, .russianTwist, .gluteBridge, .toeTouch, .superman: 2.0
        case .bicycleCrunch, .deadBug, .birdDog, .bridgeMarch, .donkeyKick, .shoulderTap: 1.8
        case .jumpingJack, .starJump, .jumpSquat, .skater, .plankJack, .calfRaise, .squatPulse: 1.1
        case .mountainClimber, .highKnees, .buttKick, .jumpRope, .flutterKick, .shadowBox: 0.66
        case .armCircle: 1.4
        case .plank, .sidePlank, .wallSit, .hollowHold, .bearHold: 3.0
        }
    }

    /// Static holds breathe instead of repping, so they are never counted in reps.
    nonisolated var isHold: Bool {
        switch self {
        case .plank, .sidePlank, .wallSit, .hollowHold, .bearHold: true
        default: false
        }
    }

    /// Both feet leave the floor — the moves to avoid in a flat at 6am.
    nonisolated var isExplosive: Bool {
        switch self {
        case .jumpingJack, .starJump, .jumpSquat, .skater, .jumpRope, .highKnees,
             .buttKick, .burpee, .plankJack, .mountainClimber: true
        default: false
        }
    }

    /// Plain-language name, used when a move needs to introduce itself.
    nonisolated var title: String {
        switch self {
        case .pushUp: "Push-Up"
        case .pikePushUp: "Pike Push-Up"
        case .shoulderTap: "Shoulder Tap"
        case .plank: "Plank"
        case .plankJack: "Plank Jack"
        case .sidePlank: "Side Plank"
        case .mountainClimber: "Mountain Climber"
        case .burpee: "Burpee"
        case .squatThrust: "Squat Thrust"
        case .bearHold: "Bear Hold"
        case .inchworm: "Inchworm"
        case .jumpingJack: "Jumping Jack"
        case .starJump: "Star Jump"
        case .highKnees: "High Knees"
        case .buttKick: "Butt Kick"
        case .skater: "Skater Hop"
        case .jumpRope: "Jump Rope"
        case .shadowBox: "Shadow Boxing"
        case .squat: "Squat"
        case .jumpSquat: "Jump Squat"
        case .squatPulse: "Pulse Squat"
        case .wallSit: "Wall Sit"
        case .lunge: "Lunge"
        case .splitSquat: "Split Squat"
        case .gluteBridge: "Glute Bridge"
        case .bridgeMarch: "Bridge March"
        case .donkeyKick: "Donkey Kick"
        case .calfRaise: "Calf Raise"
        case .crunch: "Crunch"
        case .sitUp: "Sit-Up"
        case .bicycleCrunch: "Bicycle Crunch"
        case .legRaise: "Leg Raise"
        case .flutterKick: "Flutter Kick"
        case .hollowHold: "Hollow Hold"
        case .russianTwist: "Russian Twist"
        case .superman: "Superman"
        case .birdDog: "Bird Dog"
        case .deadBug: "Dead Bug"
        case .chairDip: "Chair Dip"
        case .doorRow: "Door Row"
        case .toeTouch: "Toe Touch"
        case .armCircle: "Arm Circle"
        }
    }

    /// Whether the move is performed on a chair, a wall or the floor — drawn as
    /// a prop so the animation doesn't look like it is floating.
    nonisolated var prop: StickProp {
        switch self {
        case .chairDip: .box
        case .wallSit: .wall
        case .doorRow: .bar
        default: .none
        }
    }

    /// The angle the move is filmed from.
    nonisolated var facing: StickFacing {
        switch self {
        case .jumpingJack, .starJump, .highKnees, .buttKick, .skater, .jumpRope,
             .shadowBox, .armCircle, .calfRaise: .frontal
        default: .sagittal
        }
    }

    /// Moves performed lying down are shot from higher up, so the floor reads.
    nonisolated var isFloorLevel: Bool {
        switch self {
        case .crunch, .sitUp, .bicycleCrunch, .legRaise, .flutterKick, .hollowHold,
             .russianTwist, .superman, .gluteBridge, .bridgeMarch, .deadBug: true
        default: false
        }
    }

    /// Camera for this move, gently orbiting so the depth is unmistakable.
    nonisolated func camera(orbit: Double) -> StickCamera {
        StickCamera(
            yaw: facing.yaw + sin(orbit) * 0.09,
            pitch: isFloorLevel ? 0.30 : 0.15,
            lens: 7.0,
            pivot: isFloorLevel ? 0.45 : 0.85
        )
    }

    /// Keyframes of one full repetition. The loop returns to frame zero.
    nonisolated var keyframes: [StickPose] {
        switch self {
        case .pushUp: Self.pushUpFrames
        case .pikePushUp: Self.pikeFrames
        case .shoulderTap: Self.shoulderTapFrames
        case .plank: Self.plankFrames
        case .plankJack: Self.plankJackFrames
        case .sidePlank: Self.sidePlankFrames
        case .mountainClimber: Self.mountainClimberFrames
        case .burpee: Self.burpeeFrames
        case .squatThrust: Self.squatThrustFrames
        case .bearHold: Self.bearHoldFrames
        case .inchworm: Self.inchwormFrames
        case .jumpingJack: Self.jumpingJackFrames
        case .starJump: Self.starJumpFrames
        case .highKnees: Self.highKneesFrames
        case .buttKick: Self.buttKickFrames
        case .skater: Self.skaterFrames
        case .jumpRope: Self.jumpRopeFrames
        case .shadowBox: Self.shadowBoxFrames
        case .squat: Self.squatFrames
        case .jumpSquat: Self.jumpSquatFrames
        case .squatPulse: Self.squatPulseFrames
        case .wallSit: Self.wallSitFrames
        case .lunge: Self.lungeFrames
        case .splitSquat: Self.splitSquatFrames
        case .gluteBridge: Self.gluteBridgeFrames
        case .bridgeMarch: Self.bridgeMarchFrames
        case .donkeyKick: Self.donkeyKickFrames
        case .calfRaise: Self.calfRaiseFrames
        case .crunch: Self.crunchFrames
        case .sitUp: Self.sitUpFrames
        case .bicycleCrunch: Self.bicycleFrames
        case .legRaise: Self.legRaiseFrames
        case .flutterKick: Self.flutterFrames
        case .hollowHold: Self.hollowFrames
        case .russianTwist: Self.russianTwistFrames
        case .superman: Self.supermanFrames
        case .birdDog: Self.birdDogFrames
        case .deadBug: Self.deadBugFrames
        case .chairDip: Self.chairDipFrames
        case .doorRow: Self.doorRowFrames
        case .toeTouch: Self.toeTouchFrames
        case .armCircle: Self.armCircleFrames
        }
    }

    /// Pose at a normalized position in the cycle, eased so the movement
    /// accelerates and settles like a body does.
    nonisolated func pose(at phase: Double) -> StickPose {
        let frames = keyframes
        guard frames.count > 1 else { return frames.first ?? Self.standing }

        let wrapped = phase - phase.rounded(.down)
        let scaled = wrapped * Double(frames.count)
        let index = min(frames.count - 1, Int(scaled))
        let next = (index + 1) % frames.count
        let local = scaled - Double(index)
        // Smoothstep: no robotic constant-velocity limbs.
        let eased = local * local * (3 - 2 * local)
        return StickPose.lerp(frames[index], frames[next], eased)
    }

    /// Solved joints for this move at a point in its cycle.
    nonisolated func skeleton(at phase: Double) -> StickSkeleton {
        StickBody.solve(pose(at: phase), facing: facing)
    }

    /// The space this move needs, so every exercise fills its card properly
    /// instead of a burpee's jump being cropped off the top.
    nonisolated var framing: StickFraming {
        var minX = -0.75
        var maxX = 0.75
        var maxY = 1.9

        for pose in keyframes {
            let points = [
                pose.pelvis,
                pose.handNear,
                pose.handFar ?? pose.handNear,
                pose.footNear,
                pose.footFar ?? pose.footNear
            ]
            for point in points {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y + 0.12)
            }
            let radians = pose.spine * .pi / 180
            let crown = StickBody.spineLength + StickBody.neckToHead + StickBody.headRadius
            maxY = max(maxY, pose.pelvis.y + sin(radians) * crown + 0.1)
            minX = min(minX, pose.pelvis.x + cos(radians) * crown - 0.18)
            maxX = max(maxX, pose.pelvis.x + cos(radians) * crown + 0.18)
        }

        if prop == .box { minX = min(minX, -0.9) }
        if prop == .wall { minX = min(minX, -0.6) }
        if prop == .bar { maxX = max(maxX, 0.85) }

        return StickFraming(minX: minX - 0.14, maxX: maxX + 0.14, maxY: maxY)
    }
}

/// The world box a move moves inside.
nonisolated struct StickFraming: Sendable {
    let minX: Double
    let maxX: Double
    let maxY: Double

    var width: Double { max(1.7, maxX - minX) }
    var height: Double { max(2.05, maxY) }
    var centerX: Double { (minX + maxX) / 2 }
}

/// Furniture drawn behind the figure so a move has something to act on.
nonisolated enum StickProp: Sendable, Equatable {
    case none
    case box
    case wall
    case bar
}

// MARK: - Keyframe library

extension StickMove {
    nonisolated static func p(_ x: Double, _ y: Double, _ z: Double = 0) -> StickVec3 {
        StickVec3(x, y, z)
    }

    nonisolated static let standing = StickPose(
        pelvis: p(0, StickBody.standingHip),
        spine: 90,
        handNear: p(0.20, 0.78),
        handFar: p(-0.20, 0.78),
        footNear: p(0.10, 0),
        footFar: p(-0.10, 0)
    )

    // MARK: Pushing

    nonisolated static let pushUpFrames: [StickPose] = [
        StickPose(pelvis: p(-0.10, 0.42), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.27), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.05), footFar: p(-0.90, 0.05), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let pikeFrames: [StickPose] = [
        StickPose(pelvis: p(-0.12, 0.84), spine: -52, handNear: p(0.30, 0), handFar: p(0.30, 0),
                  footNear: p(-0.22, 0.03), footFar: p(-0.22, 0.03), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.14, 0.76), spine: -68, handNear: p(0.30, 0), handFar: p(0.30, 0),
                  footNear: p(-0.22, 0.03), footFar: p(-0.22, 0.03), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let shoulderTapFrames: [StickPose] = [
        StickPose(pelvis: p(-0.10, 0.44), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.44), spine: 19, handNear: p(0.26, 0.50, -0.16), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.44), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.44), spine: 19, handNear: p(0.44, 0), handFar: p(0.26, 0.50, 0.16),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let plankFrames: [StickPose] = [
        StickPose(pelvis: p(-0.10, 0.42), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.45), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.06), footFar: p(-0.90, 0.06), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let plankJackFrames: [StickPose] = [
        StickPose(pelvis: p(-0.10, 0.43), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.88, 0.05), footFar: p(-0.88, 0.05), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.41), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.86, 0.06, 0.22), footFar: p(-0.86, 0.06, -0.22),
                  elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let sidePlankFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.46), spine: 24, handNear: p(0.45, 1.28, 0.10), handFar: p(0.60, 0.02, -0.05),
                  footNear: p(-0.72, 0.06), footFar: p(-0.72, 0.06), elbowBend: .down, kneeBend: .down),
        StickPose(pelvis: p(0, 0.50), spine: 24, handNear: p(0.46, 1.30, 0.10), handFar: p(0.60, 0.02, -0.05),
                  footNear: p(-0.72, 0.06), footFar: p(-0.72, 0.06), elbowBend: .down, kneeBend: .down)
    ]

    nonisolated static let mountainClimberFrames: [StickPose] = [
        StickPose(pelvis: p(-0.10, 0.46), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.26, 0.24), footFar: p(-0.88, 0.06), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.10, 0.46), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.88, 0.06), footFar: p(-0.26, 0.24), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let bearHoldFrames: [StickPose] = [
        StickPose(pelvis: p(-0.26, 0.54), spine: -8, handNear: p(0.36, 0), handFar: p(0.36, 0),
                  footNear: p(-0.62, 0.02), footFar: p(-0.62, 0.02), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.26, 0.57), spine: -8, handNear: p(0.36, 0), handFar: p(0.36, 0),
                  footNear: p(-0.62, 0.02), footFar: p(-0.62, 0.02), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let burpeeFrames: [StickPose] = [
        standing,
        StickPose(pelvis: p(-0.12, 0.46), spine: 42, handNear: p(0.36, 0.22), handFar: p(0.32, 0.20),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.10, 0.30), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.05), footFar: p(-0.90, 0.05), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.12, 0.46), spine: 42, handNear: p(0.36, 0.22), handFar: p(0.32, 0.20),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 1.12), spine: 92, handNear: p(0.34, 2.10), handFar: p(0.30, 2.08),
                  footNear: p(0.10, 0.28), footFar: p(0.06, 0.28), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let squatThrustFrames: [StickPose] = [
        StickPose(pelvis: p(-0.12, 0.46), spine: 42, handNear: p(0.36, 0.22), handFar: p(0.32, 0.20),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.10, 0.30), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.05), footFar: p(-0.90, 0.05), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let inchwormFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.86), spine: 46, handNear: p(0.30, 0.60), handFar: p(0.26, 0.58),
                  footNear: p(0.06, 0), footFar: p(0.02, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.10, 0.80), spine: -40, handNear: p(0.42, 0), handFar: p(0.42, 0),
                  footNear: p(-0.28, 0.02), footFar: p(-0.28, 0.02), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.34), spine: 19, handNear: p(0.44, 0), handFar: p(0.44, 0),
                  footNear: p(-0.90, 0.05), footFar: p(-0.90, 0.05), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.10, 0.80), spine: -40, handNear: p(0.42, 0), handFar: p(0.42, 0),
                  footNear: p(-0.28, 0.02), footFar: p(-0.28, 0.02), elbowBend: .back, kneeBend: .down)
    ]

    // MARK: Standing cardio

    nonisolated static let jumpingJackFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.22, 0.78), handFar: p(-0.22, 0.78),
                  footNear: p(0.11, 0), footFar: p(-0.11, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.82), spine: 90, handNear: p(0.58, 1.86), handFar: p(-0.58, 1.86),
                  footNear: p(0.44, 0.02), footFar: p(-0.44, 0.02), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let starJumpFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.54), spine: 86, handNear: p(0.28, 0.50), handFar: p(-0.28, 0.50),
                  footNear: p(0.18, 0), footFar: p(-0.18, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 1.14), spine: 90, handNear: p(0.62, 2.08), handFar: p(-0.62, 2.08),
                  footNear: p(0.54, 0.44), footFar: p(-0.54, 0.44), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let highKneesFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.90), spine: 92, handNear: p(0.26, 1.00, -0.24), handFar: p(-0.30, 1.10, 0.28),
                  footNear: p(0.20, 0.46, 0.18), footFar: p(-0.10, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.90), spine: 92, handNear: p(0.30, 1.10, 0.28), handFar: p(-0.26, 1.00, -0.24),
                  footNear: p(0.10, 0), footFar: p(-0.20, 0.46, 0.18), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let buttKickFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 92, handNear: p(0.26, 1.00, -0.20), handFar: p(-0.30, 1.08, 0.24),
                  footNear: p(0.10, 0.60, -0.26), footFar: p(-0.10, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.88), spine: 92, handNear: p(0.30, 1.08, 0.24), handFar: p(-0.26, 1.00, -0.20),
                  footNear: p(0.10, 0), footFar: p(-0.10, 0.60, -0.26), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let skaterFrames: [StickPose] = [
        StickPose(pelvis: p(0.26, 0.66), spine: 78, handNear: p(-0.02, 1.06), handFar: p(0.56, 1.32),
                  footNear: p(0.38, 0), footFar: p(-0.06, 0.34, -0.22), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.26, 0.66), spine: 102, handNear: p(0.02, 1.06), handFar: p(-0.56, 1.32),
                  footNear: p(-0.38, 0), footFar: p(0.06, 0.34, -0.22), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let jumpRopeFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.86), spine: 90, handNear: p(0.40, 0.92, 0.10), handFar: p(-0.40, 0.92, 0.10),
                  footNear: p(0.10, 0), footFar: p(-0.10, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.98), spine: 90, handNear: p(0.42, 1.00, 0.10), handFar: p(-0.42, 1.00, 0.10),
                  footNear: p(0.10, 0.16), footFar: p(-0.10, 0.16), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let shadowBoxFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.84), spine: 88, twist: 14, handNear: p(0.20, 1.32, 0.62),
                  handFar: p(-0.22, 1.34, 0.22), footNear: p(0.22, 0), footFar: p(-0.22, 0),
                  elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.84), spine: 92, twist: -14, handNear: p(0.22, 1.34, 0.22),
                  handFar: p(-0.20, 1.32, 0.62), footNear: p(0.22, 0), footFar: p(-0.22, 0),
                  elbowBend: .back, kneeBend: .forward)
    ]

    /// A true circle around the shoulder — up, forward, down, back — which only
    /// reads as a circle because the arm can travel in depth.
    nonisolated static let armCircleFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.22, 2.02), handFar: p(-0.22, 2.02),
                  footNear: p(0.11, 0), footFar: p(-0.11, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.20, 1.42, 0.60), handFar: p(-0.20, 1.42, 0.60),
                  footNear: p(0.11, 0), footFar: p(-0.11, 0), elbowBend: .down, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.20, 0.82), handFar: p(-0.20, 0.82),
                  footNear: p(0.11, 0), footFar: p(-0.11, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.20, 1.42, -0.60), handFar: p(-0.20, 1.42, -0.60),
                  footNear: p(0.11, 0), footFar: p(-0.11, 0), elbowBend: .up, kneeBend: .forward)
    ]

    // MARK: Legs

    nonisolated static let squatFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.24, 0.80), handFar: p(0.20, 0.78),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.16, 0.46), spine: 62, handNear: p(0.60, 0.98), handFar: p(0.56, 0.96),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let jumpSquatFrames: [StickPose] = [
        StickPose(pelvis: p(-0.16, 0.46), spine: 62, handNear: p(-0.22, 0.42), handFar: p(-0.26, 0.40),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 1.16), spine: 92, handNear: p(0.30, 2.06), handFar: p(0.26, 2.04),
                  footNear: p(0.10, 0.32), footFar: p(0.06, 0.32), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let squatPulseFrames: [StickPose] = [
        StickPose(pelvis: p(-0.14, 0.52), spine: 64, handNear: p(0.56, 1.00), handFar: p(0.52, 0.98),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.16, 0.42), spine: 62, handNear: p(0.54, 0.92), handFar: p(0.50, 0.90),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let wallSitFrames: [StickPose] = [
        StickPose(pelvis: p(-0.30, 0.48), spine: 90, handNear: p(0.06, 0.52), handFar: p(0.02, 0.50),
                  footNear: p(0.16, 0), footFar: p(0.12, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.30, 0.46), spine: 90, handNear: p(0.06, 0.50), handFar: p(0.02, 0.48),
                  footNear: p(0.16, 0), footFar: p(0.12, 0), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let lungeFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.20, 0.78), handFar: p(0.16, 0.76),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.02, 0.54), spine: 88, handNear: p(0.20, 0.46), handFar: p(0.16, 0.44),
                  footNear: p(0.42, 0), footFar: p(-0.44, 0.16), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.20, 0.78), handFar: p(0.16, 0.76),
                  footNear: p(0.08, 0), footFar: p(0.04, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.02, 0.54), spine: 88, handNear: p(0.20, 0.46), handFar: p(0.16, 0.44),
                  footNear: p(-0.44, 0.16), footFar: p(0.42, 0), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let splitSquatFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.82), spine: 90, handNear: p(0.18, 0.74), handFar: p(0.14, 0.72),
                  footNear: p(0.36, 0), footFar: p(-0.40, 0.10), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.52), spine: 88, handNear: p(0.18, 0.44), handFar: p(0.14, 0.42),
                  footNear: p(0.36, 0), footFar: p(-0.40, 0.10), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let calfRaiseFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.20, 0.78), handFar: p(-0.20, 0.78),
                  footNear: p(0.11, 0), footFar: p(-0.11, 0), elbowBend: .back, kneeBend: .back),
        StickPose(pelvis: p(0, 1.00), spine: 90, handNear: p(0.20, 0.90), handFar: p(-0.20, 0.90),
                  footNear: p(0.11, 0.12), footFar: p(-0.11, 0.12), elbowBend: .back, kneeBend: .back)
    ]

    nonisolated static let toeTouchFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.88), spine: 90, handNear: p(0.26, 2.02), handFar: p(0.22, 2.00),
                  footNear: p(0.12, 0), footFar: p(0.08, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(0, 0.80), spine: 2, handNear: p(0.30, 0.18), handFar: p(0.26, 0.16),
                  footNear: p(0.12, 0), footFar: p(0.08, 0), elbowBend: .down, kneeBend: .forward)
    ]

    // MARK: Floor — posterior

    nonisolated static let gluteBridgeFrames: [StickPose] = [
        StickPose(pelvis: p(-0.20, 0.12), spine: -4, handNear: p(-0.24, 0.05), handFar: p(-0.28, 0.05),
                  footNear: p(-0.72, 0.03), footFar: p(-0.72, 0.03), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.20, 0.42), spine: -26, handNear: p(-0.24, 0.05), handFar: p(-0.28, 0.05),
                  footNear: p(-0.72, 0.03), footFar: p(-0.72, 0.03), elbowBend: .down, kneeBend: .up)
    ]

    nonisolated static let bridgeMarchFrames: [StickPose] = [
        StickPose(pelvis: p(-0.20, 0.42), spine: -26, handNear: p(-0.24, 0.05), handFar: p(-0.28, 0.05),
                  footNear: p(-0.72, 0.03), footFar: p(-0.72, 0.03), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.20, 0.42), spine: -26, handNear: p(-0.24, 0.05), handFar: p(-0.28, 0.05),
                  footNear: p(-0.50, 0.52), footFar: p(-0.72, 0.03), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.20, 0.42), spine: -26, handNear: p(-0.24, 0.05), handFar: p(-0.28, 0.05),
                  footNear: p(-0.72, 0.03), footFar: p(-0.72, 0.03), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.20, 0.42), spine: -26, handNear: p(-0.24, 0.05), handFar: p(-0.28, 0.05),
                  footNear: p(-0.72, 0.03), footFar: p(-0.50, 0.52), elbowBend: .down, kneeBend: .up)
    ]

    nonisolated static let donkeyKickFrames: [StickPose] = [
        StickPose(pelvis: p(-0.30, 0.52), spine: -6, handNear: p(0.32, 0.02), handFar: p(0.28, 0.02),
                  footNear: p(-0.66, 0.03), footFar: p(-0.66, 0.03), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.30, 0.52), spine: -6, handNear: p(0.32, 0.02), handFar: p(0.28, 0.02),
                  footNear: p(-0.90, 0.84), footFar: p(-0.66, 0.03), elbowBend: .back, kneeBend: .down)
    ]

    nonisolated static let supermanFrames: [StickPose] = [
        StickPose(pelvis: p(0, 0.06), spine: 4, handNear: p(1.14, 0.08), handFar: p(1.10, 0.08),
                  footNear: p(-0.86, 0.05), footFar: p(-0.90, 0.05), elbowBend: .down, kneeBend: .down),
        StickPose(pelvis: p(0, 0.08), spine: 14, handNear: p(1.10, 0.46), handFar: p(1.06, 0.44),
                  footNear: p(-0.84, 0.34), footFar: p(-0.88, 0.32), elbowBend: .down, kneeBend: .down)
    ]

    nonisolated static let birdDogFrames: [StickPose] = [
        StickPose(pelvis: p(-0.30, 0.52), spine: -6, handNear: p(0.32, 0.02), handFar: p(0.28, 0.02),
                  footNear: p(-0.66, 0.03), footFar: p(-0.66, 0.03), elbowBend: .back, kneeBend: .down),
        StickPose(pelvis: p(-0.30, 0.52), spine: -6, handNear: p(0.84, 0.62), handFar: p(0.28, 0.02),
                  footNear: p(-0.66, 0.03), footFar: p(-0.98, 0.60), elbowBend: .back, kneeBend: .down)
    ]

    // MARK: Floor — core

    nonisolated static let crunchFrames: [StickPose] = [
        StickPose(pelvis: p(-0.22, 0.10), spine: -2, handNear: p(0.52, 0.30), handFar: p(0.48, 0.28),
                  footNear: p(-0.74, 0.03), footFar: p(-0.74, 0.03), elbowBend: .up, kneeBend: .up),
        StickPose(pelvis: p(-0.22, 0.10), spine: 30, handNear: p(0.44, 0.60), handFar: p(0.40, 0.58),
                  footNear: p(-0.74, 0.03), footFar: p(-0.74, 0.03), elbowBend: .up, kneeBend: .up)
    ]

    nonisolated static let sitUpFrames: [StickPose] = [
        StickPose(pelvis: p(-0.22, 0.10), spine: -2, handNear: p(0.52, 0.30), handFar: p(0.48, 0.28),
                  footNear: p(-0.74, 0.03), footFar: p(-0.74, 0.03), elbowBend: .up, kneeBend: .up),
        StickPose(pelvis: p(-0.22, 0.10), spine: 66, handNear: p(0.18, 0.80), handFar: p(0.14, 0.78),
                  footNear: p(-0.74, 0.03), footFar: p(-0.74, 0.03), elbowBend: .up, kneeBend: .up)
    ]

    nonisolated static let bicycleFrames: [StickPose] = [
        StickPose(pelvis: p(-0.20, 0.12), spine: 24, twist: 26, handNear: p(0.44, 0.58), handFar: p(0.40, 0.56),
                  footNear: p(-0.46, 0.46), footFar: p(-0.92, 0.20), elbowBend: .up, kneeBend: .up),
        StickPose(pelvis: p(-0.20, 0.12), spine: 24, twist: -26, handNear: p(0.44, 0.58), handFar: p(0.40, 0.56),
                  footNear: p(-0.92, 0.20), footFar: p(-0.46, 0.46), elbowBend: .up, kneeBend: .up)
    ]

    nonisolated static let legRaiseFrames: [StickPose] = [
        StickPose(pelvis: p(-0.16, 0.10), spine: -2, handNear: p(-0.20, 0.05), handFar: p(-0.24, 0.05),
                  footNear: p(-1.04, 0.10), footFar: p(-1.04, 0.10), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.16, 0.10), spine: -2, handNear: p(-0.20, 0.05), handFar: p(-0.24, 0.05),
                  footNear: p(-0.30, 0.94), footFar: p(-0.30, 0.94), elbowBend: .down, kneeBend: .up)
    ]

    nonisolated static let flutterFrames: [StickPose] = [
        StickPose(pelvis: p(-0.16, 0.10), spine: -2, handNear: p(-0.20, 0.05), handFar: p(-0.24, 0.05),
                  footNear: p(-0.98, 0.34), footFar: p(-1.02, 0.08), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.16, 0.10), spine: -2, handNear: p(-0.20, 0.05), handFar: p(-0.24, 0.05),
                  footNear: p(-1.02, 0.08), footFar: p(-0.98, 0.34), elbowBend: .down, kneeBend: .up)
    ]

    nonisolated static let hollowFrames: [StickPose] = [
        StickPose(pelvis: p(-0.14, 0.16), spine: 14, handNear: p(0.72, 0.60), handFar: p(0.68, 0.58),
                  footNear: p(-0.96, 0.42), footFar: p(-0.98, 0.40), elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.14, 0.18), spine: 16, handNear: p(0.74, 0.64), handFar: p(0.70, 0.62),
                  footNear: p(-0.96, 0.46), footFar: p(-0.98, 0.44), elbowBend: .down, kneeBend: .up)
    ]

    nonisolated static let russianTwistFrames: [StickPose] = [
        StickPose(pelvis: p(-0.18, 0.16), spine: 46, twist: 32, handNear: p(0.34, 0.34, 0.40),
                  handFar: p(0.30, 0.32, 0.36), footNear: p(-0.68, 0.20), footFar: p(-0.68, 0.20),
                  elbowBend: .down, kneeBend: .up),
        StickPose(pelvis: p(-0.18, 0.16), spine: 46, twist: -32, handNear: p(0.34, 0.34, -0.36),
                  handFar: p(0.30, 0.32, -0.40), footNear: p(-0.68, 0.20), footFar: p(-0.68, 0.20),
                  elbowBend: .down, kneeBend: .up)
    ]

    nonisolated static let deadBugFrames: [StickPose] = [
        StickPose(pelvis: p(-0.16, 0.10), spine: -2, handNear: p(0.40, 0.66), handFar: p(0.36, 0.64),
                  footNear: p(-0.52, 0.58), footFar: p(-0.56, 0.56), elbowBend: .up, kneeBend: .up),
        StickPose(pelvis: p(-0.16, 0.10), spine: -2, handNear: p(0.98, 0.14), handFar: p(0.36, 0.64),
                  footNear: p(-0.52, 0.58), footFar: p(-1.04, 0.14), elbowBend: .up, kneeBend: .up)
    ]

    // MARK: Props

    nonisolated static let chairDipFrames: [StickPose] = [
        StickPose(pelvis: p(-0.08, 0.50), spine: 76, handNear: p(-0.34, 0.48), handFar: p(-0.38, 0.46),
                  footNear: p(0.52, 0), footFar: p(0.48, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.08, 0.28), spine: 76, handNear: p(-0.34, 0.48), handFar: p(-0.38, 0.46),
                  footNear: p(0.52, 0), footFar: p(0.48, 0), elbowBend: .back, kneeBend: .forward)
    ]

    nonisolated static let doorRowFrames: [StickPose] = [
        StickPose(pelvis: p(-0.10, 0.80), spine: 100, handNear: p(0.44, 1.20), handFar: p(0.44, 1.18),
                  footNear: p(0.24, 0), footFar: p(0.20, 0), elbowBend: .back, kneeBend: .forward),
        StickPose(pelvis: p(-0.04, 0.84), spine: 100, handNear: p(0.30, 1.24), handFar: p(0.30, 1.22),
                  footNear: p(0.24, 0), footFar: p(0.20, 0), elbowBend: .back, kneeBend: .forward)
    ]
}
