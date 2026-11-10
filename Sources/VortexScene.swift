import AppKit
import AVFoundation
import SpriteKit

enum VortexPhase {
    case ready, playing, paused, gameOver
}

private final class VortexSounds {
    static let shared = VortexSounds()
    private var sounds: [String: Data] = [:]
    private var active: [AVAudioPlayer] = []

    func play(_ effect: String, enabled: Bool) {
        guard enabled else { return }
        active.removeAll { !$0.isPlaying }
        let data: Data
        if let existing = sounds[effect] {
            data = existing
        } else {
            data = makeWAV(effect)
            sounds[effect] = data
        }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = effect == "damage" ? 0.6 : 0.38
        player.prepareToPlay()
        player.play()
        active.append(player)
    }

    private func makeWAV(_ effect: String) -> Data {
        let rate = 22_050
        let duration: Double
        switch effect {
        case "shot": duration = 0.085
        case "hit": duration = 0.16
        case "damage": duration = 0.42
        case "pulse": duration = 0.52
        default: duration = 0.28
        }
        let count = Int(Double(rate) * duration)
        var data = Data()
        func u16(_ value: UInt16) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
        }
        func u32(_ value: UInt32) {
            for i in 0..<4 { data.append(UInt8((value >> (i * 8)) & 0xff)) }
        }
        let length = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        u32(36 + length)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(rate))
        u32(UInt32(rate * 2))
        u16(2)
        u16(16)
        data.append(contentsOf: Array("data".utf8))
        u32(length)
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let fraction = t / duration
            let frequency: Double
            switch effect {
            case "shot": frequency = 650 - 330 * fraction
            case "hit": frequency = 200 + 500 * fraction
            case "damage": frequency = 180 - 140 * fraction
            case "pulse": frequency = 130 + 1_000 * fraction
            default: frequency = 370 + 150 * fraction
            }
            let env = pow(max(0, 1 - fraction), effect == "pulse" ? 1.0 : 2.1)
            let a = sin(2 * Double.pi * frequency * t)
            let b = sin(2 * Double.pi * frequency * 1.99 * t)
            let noise = sin(2 * Double.pi * 2_933 * t) * sin(2 * Double.pi * 1_619 * t)
            let sample = (a * 0.65 + b * 0.22 + noise * 0.13) * env * 0.72
            let pcm = Int16(max(-32_767, min(32_767, Int(sample * 32_767))))
            u16(UInt16(bitPattern: pcm))
        }
        return data
    }
}

private struct VortexSpark {
    var position: CGPoint
    var velocity: CGVector
    var color: NSColor
    var age: Double = 0
}

final class VortexScene: SKScene {
    var modern = false
    var soundOn = true
    private(set) var phase: VortexPhase = .ready
    private(set) var difficulty = "Veteran"
    private(set) var rules = VortexRules()
    private(set) var score = 0
    private(set) var wave = 1
    private(set) var lives = 3

    private var lane = 0
    private var enemies: [VortexEnemy] = []
    private var shots: [VortexShot] = []
    private var sparks: [VortexSpark] = []
    private var held = Set<UInt16>()
    private var shiftDown = false
    private var spawnRemaining = 0
    private var spawnClock = 0.0
    private var spawnIndex = 0
    private var fireClock = 0.3
    private var moveClock = 0.0
    private var pulseAvailable = true
    private var ammo = 500
    private var rechargeFraction = 0.0
    private var shotIdle = 0.0
    private var shotsFired = 0
    private var shotsHit = 0
    private var invulnerable = 0.0
    private var gameTime = 0.0
    private var flash = 0.0
    private var announcement = 0.0
    private var pulseVisual = 0.0
    private var lastFrame: TimeInterval = 0

    private let backgroundLayer = SKNode()
    private let arenaLayer = SKNode()
    private let hudLayer = SKNode()
    private let overlayLayer = SKNode()

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        addChild(backgroundLayer)
        addChild(arenaLayer)
        addChild(hudLayer)
        addChild(overlayLayer)
        prepareBackground()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("Use init(size:)") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        prepareBackground()
    }

    func start(difficulty: String, custom: VortexRules? = nil) {
        self.difficulty = custom == nil ? difficulty : "Custom"
        rules = (custom ?? VortexRules.standard(difficulty)).validated()
        phase = .playing
        score = 0
        wave = 1
        lives = rules.startingLives
        lane = 0
        enemies.removeAll()
        shots.removeAll()
        sparks.removeAll()
        held.removeAll()
        fireClock = 0.3
        moveClock = 0
        ammo = 500
        rechargeFraction = 0
        shotIdle = 0
        shotsFired = 0
        shotsHit = 0
        invulnerable = 1.25
        gameTime = 0
        flash = 0
        beginWave()
        VortexSounds.shared.play("wave", enabled: soundOn)
    }

    func togglePause() {
        switch phase {
        case .playing: phase = .paused; held.removeAll()
        case .paused: phase = .playing
        default: break
        }
    }

    func snapshot() -> VortexSnapshot? {
        guard phase == .playing || phase == .paused else { return nil }
        return VortexSnapshot(difficulty: difficulty, modern: modern, rules: rules,
                              score: score, lives: lives, wave: wave, lane: lane,
                              spawnRemaining: spawnRemaining, spawnClock: spawnClock,
                              spawnIndex: spawnIndex, pulseAvailable: pulseAvailable,
                              ammo: ammo, rechargeFraction: rechargeFraction,
                              shotIdle: shotIdle, shotsFired: shotsFired, shotsHit: shotsHit,
                              invulnerable: invulnerable, gameTime: gameTime,
                              enemies: enemies, shots: shots)
    }

    func restore(_ save: VortexSnapshot) {
        guard save.version == 1 else { return }
        difficulty = save.difficulty
        modern = save.modern
        rules = save.rules.validated()
        score = max(0, save.score)
        lives = max(1, save.lives)
        wave = max(1, save.wave)
        lane = modulo(save.lane, rules.lanes)
        spawnRemaining = max(0, save.spawnRemaining)
        spawnClock = max(0, save.spawnClock)
        spawnIndex = max(0, save.spawnIndex)
        pulseAvailable = save.pulseAvailable
        ammo = max(0, min(500, save.ammo))
        rechargeFraction = save.rechargeFraction
        shotIdle = save.shotIdle
        shotsFired = save.shotsFired
        shotsHit = save.shotsHit
        invulnerable = 1.0
        gameTime = save.gameTime
        enemies = save.enemies
        shots = save.shots
        sparks.removeAll()
        phase = .playing
        announcement = 1.0
        flash = 0
        lastFrame = 0
    }

    func press(_ key: UInt16, repeatKey: Bool, modifiers: NSEvent.ModifierFlags) {
        if key == 36 || key == 76 {
            if phase == .ready || phase == .gameOver { start(difficulty: difficulty) }
            else if phase == .paused { togglePause() }
            return
        }
        if key == 35 && !repeatKey { togglePause(); return }
        if key == 18 && !repeatKey { modern = false }
        if key == 19 && !repeatKey { modern = true }
        if modifiers.contains(.shift) {
            if !shiftDown && phase == .playing { pulse() }
            shiftDown = true
        }
        guard phase == .playing else { return }
        held.insert(key)
        if !repeatKey && (key == 123 || key == 0) {
            lane = modulo(lane - 1, rules.lanes)
            moveClock = 0
        }
        if !repeatKey && (key == 124 || key == 2) {
            lane = modulo(lane + 1, rules.lanes)
            moveClock = 0
        }
        if key == 49 && !repeatKey { fire() }
    }

    func release(_ key: UInt16) { held.remove(key) }

    func shiftChanged(_ pressed: Bool) {
        if pressed && !shiftDown && phase == .playing { pulse() }
        shiftDown = pressed
    }

    override func update(_ currentTime: TimeInterval) {
        if lastFrame == 0 { lastFrame = currentTime }
        let dt = min(0.05, max(0, currentTime - lastFrame))
        lastFrame = currentTime
        if phase == .playing { advance(dt) }
        flash = max(0, flash - dt * 2.2)
        pulseVisual = max(0, pulseVisual - dt * 1.7)
        announcement = max(0, announcement - dt)
        for i in sparks.indices {
            sparks[i].age += dt
            sparks[i].position.x += sparks[i].velocity.dx * dt
            sparks[i].position.y += sparks[i].velocity.dy * dt
        }
        sparks.removeAll { $0.age > 0.45 }
        render()
    }

    private func modulo(_ x: Int, _ n: Int) -> Int { ((x % n) + n) % n }

    private func beginWave() {
        spawnRemaining = rules.count(for: wave)
        spawnClock = 0.65
        spawnIndex = 0
        pulseAvailable = true
        announcement = 1.8
    }

    private func spawn() {
        let variety = (spawnIndex + wave * 3) % 8
        let kind: VortexEnemyKind
        if rules.armored && wave >= 2 && variety == 0 { kind = .armored }
        else if rules.flippers && wave >= 2 && (variety == 2 || variety == 5) { kind = .flipper }
        else { kind = .crawler }
        let laneIndex = modulo(spawnIndex * 7 + wave * 3 + (spawnIndex / 3) * 5, rules.lanes)
        enemies.append(VortexEnemy(lane: laneIndex, depth: 0.045, kind: kind,
                                   hp: kind == .armored ? 2 : 1,
                                   direction: spawnIndex.isMultiple(of: 2) ? 1 : -1))
        spawnIndex += 1
        spawnRemaining -= 1
    }

    private func advance(_ dt: Double) {
        gameTime += dt
        invulnerable = max(0, invulnerable - dt)
        moveClock += dt
        fireClock += dt
        shotIdle += dt

        let left = held.contains(123) || held.contains(0)
        let right = held.contains(124) || held.contains(2)
        if moveClock >= rules.moveInterval && left != right {
            lane = modulo(lane + (right ? 1 : -1), rules.lanes)
            moveClock = 0
        }
        if held.contains(49) && fireClock >= rules.fireInterval { fire() }

        if !held.contains(49) && shotIdle >= 5 && ammo < 500 {
            rechargeFraction += dt * 100
            let count = Int(rechargeFraction)
            if count > 0 {
                ammo = min(500, ammo + count)
                rechargeFraction -= Double(count)
            }
        }

        spawnClock -= dt
        if spawnClock <= 0 && spawnRemaining > 0 {
            spawn()
            spawnClock = max(0.19, 0.85 - Double(wave) * 0.025) / max(0.5, rules.enemySpeed)
        }

        for i in shots.indices { shots[i].depth -= dt * 2.25 }
        shots.removeAll { $0.depth < -0.05 }

        for i in enemies.indices {
            enemies[i].age += dt
            if enemies[i].runner {
                if enemies[i].age > max(0.095, 0.22 / rules.enemySpeed) {
                    enemies[i].lane = modulo(enemies[i].lane + enemies[i].direction, rules.lanes)
                    enemies[i].age = 0
                }
            } else {
                enemies[i].depth += dt * (0.10 + Double(wave) * 0.006) * rules.enemySpeed
                if enemies[i].kind == .flipper && enemies[i].age > 0.47 / rules.enemySpeed {
                    enemies[i].lane = modulo(enemies[i].lane + enemies[i].direction, rules.lanes)
                    enemies[i].age = 0
                }
            }
        }

        var usedShots = Set<UUID>()
        var deadEnemies = Set<UUID>()
        for shot in shots {
            guard !usedShots.contains(shot.id) else { continue }
            guard let i = enemies.indices.first(where: { index in
                let e = enemies[index]
                return !e.runner && !deadEnemies.contains(e.id) &&
                       e.lane == shot.lane && abs(e.depth - shot.depth) < 0.075
            }) else { continue }
            usedShots.insert(shot.id)
            shotsHit += 1
            enemies[i].hp -= 1
            let target = enemies[i]
            burst(at: point(lane: target.lane, depth: target.depth), color: color(for: target.kind))
            if target.hp <= 0 {
                deadEnemies.insert(target.id)
                score += target.kind == .armored ? 180 : target.kind == .flipper ? 140 : 100
            }
            VortexSounds.shared.play("hit", enabled: soundOn)
        }
        shots.removeAll { usedShots.contains($0.id) }
        enemies.removeAll { deadEnemies.contains($0.id) }

        var escaped = Set<UUID>()
        for i in enemies.indices where !enemies[i].runner && enemies[i].depth >= 1.0 {
            if rules.runners {
                enemies[i].runner = true
                enemies[i].depth = 1.04
                enemies[i].age = 0
            } else {
                escaped.insert(enemies[i].id)
                takeDamage()
            }
        }
        enemies.removeAll { escaped.contains($0.id) }

        if invulnerable <= 0 && enemies.contains(where: { $0.runner && $0.lane == lane }) {
            let hitLane = lane
            enemies.removeAll { $0.runner && $0.lane == hitLane }
            takeDamage()
        }
        if phase == .playing && spawnRemaining == 0 && enemies.isEmpty {
            wave += 1
            score += 250
            beginWave()
            VortexSounds.shared.play("wave", enabled: soundOn)
        }
        if score > VortexStore.highScore { VortexStore.highScore = score }
    }

    private func takeDamage() {
        guard invulnerable <= 0 && phase == .playing else { return }
        lives -= 1
        invulnerable = 1.8
        flash = 1
        VortexSounds.shared.play("damage", enabled: soundOn)
        burst(at: point(lane: lane, depth: 1.05), color: .systemRed)
        if lives <= 0 {
            lives = 0
            phase = .gameOver
            held.removeAll()
        }
    }

    private func fire() {
        guard phase == .playing, ammo > 0, fireClock >= rules.fireInterval else { return }
        fireClock = 0
        shotIdle = 0
        rechargeFraction = 0
        ammo -= 1
        shotsFired += 1
        shots.append(VortexShot(lane: lane, depth: 0.96))
        VortexSounds.shared.play("shot", enabled: soundOn)
    }

    private func pulse() {
        guard rules.pulse && pulseAvailable else { return }
        pulseAvailable = false
        pulseVisual = 1
        var destroyed = Set<UUID>()
        for enemy in enemies where enemy.runner || enemy.depth > 0.28 {
            destroyed.insert(enemy.id)
            score += 60
            burst(at: point(lane: enemy.lane, depth: min(1.05, enemy.depth)), color: .systemPink)
        }
        enemies.removeAll { destroyed.contains($0.id) }
        VortexSounds.shared.play("pulse", enabled: soundOn)
    }

    private func burst(at origin: CGPoint, color: NSColor) {
        for i in 0..<9 {
            let angle = Double(i) * .pi * 2 / 9 + Double(i % 3) * 0.2
            let speed = CGFloat(38 + (i * 23) % 86)
            sparks.append(VortexSpark(position: origin,
                                      velocity: CGVector(dx: CGFloat(cos(angle)) * speed,
                                                         dy: CGFloat(sin(angle)) * speed),
                                      color: color))
        }
    }

    private var center: CGPoint { CGPoint(x: size.width * 0.423, y: size.height * 0.515) }
    private var radius: CGFloat { min(size.height * 0.426, size.width * 0.355) }

    private func spokeFactor(_ index: Int) -> CGFloat {
        let a = Double(modulo(index, rules.lanes)) * 2 * Double.pi / Double(rules.lanes)
        switch wave % 4 {
        case 1: return 1
        case 2: return index.isMultiple(of: 2) ? 1.0 : 0.77
        case 3: return CGFloat(0.90 + 0.10 * cos(4 * a))
        default: return CGFloat(0.86 + 0.12 * cos(2 * a))
        }
    }

    private func boundary(spoke index: Int, depth: Double) -> CGPoint {
        let angle = (Double(index) / Double(rules.lanes)) * 2 * Double.pi + Double.pi / 2
        let x = max(0, min(1.12, depth))
        let r = radius * CGFloat(0.145 + 0.855 * pow(x, 1.20))
        let factor = 1 + (spokeFactor(index) - 1) * CGFloat(x)
        return CGPoint(x: center.x + cos(angle) * r * factor,
                       y: center.y + sin(angle) * r * factor)
    }

    private func point(lane index: Int, depth: Double) -> CGPoint {
        let a = boundary(spoke: index, depth: depth)
        let b = boundary(spoke: index + 1, depth: depth)
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private func color(for kind: VortexEnemyKind) -> NSColor {
        switch kind {
        case .crawler: return modern ? .systemMint : .systemYellow
        case .flipper: return .systemPink
        case .armored: return .systemOrange
        }
    }

    private func path(_ points: [CGPoint], close: Bool = false) -> CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first)
        for next in points.dropFirst() { p.addLine(to: next) }
        if close { p.closeSubpath() }
        return p
    }

    private func line(_ points: [CGPoint], color: NSColor, width: CGFloat = 1.5,
                      glow: CGFloat = 0, alpha: CGFloat = 1, close: Bool = false,
                      into parent: SKNode) {
        let node = SKShapeNode(path: path(points, close: close))
        node.strokeColor = color
        node.lineWidth = width
        node.glowWidth = glow
        node.alpha = alpha
        node.lineJoin = .round
        parent.addChild(node)
    }

    private func fill(_ points: [CGPoint], color: NSColor, alpha: CGFloat,
                      into parent: SKNode) {
        let node = SKShapeNode(path: path(points, close: true))
        node.strokeColor = .clear
        node.fillColor = color
        node.alpha = alpha
        parent.addChild(node)
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, size fontSize: CGFloat,
                       color: NSColor, align: SKLabelHorizontalAlignmentMode = .left,
                       into parent: SKNode, bold: Bool = false) {
        let node = SKLabelNode(text: text)
        node.fontName = bold ? "Menlo-Bold" : "Menlo"
        node.fontSize = fontSize
        node.fontColor = color
        node.horizontalAlignmentMode = align
        node.verticalAlignmentMode = .center
        node.position = CGPoint(x: x, y: y)
        parent.addChild(node)
    }

    private func prepareBackground() {
        backgroundLayer.removeAllChildren()
        let bg = SKSpriteNode(color: NSColor(calibratedRed: 0.014, green: 0.018, blue: 0.045, alpha: 1), size: size)
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundLayer.addChild(bg)
        for i in 0..<90 {
            let x = CGFloat((i * 163 + 41) % 997) / 997 * size.width
            let y = CGFloat((i * 379 + 23) % 991) / 991 * size.height
            let r: CGFloat = i.isMultiple(of: 11) ? 1.35 : 0.65
            let dot = SKShapeNode(circleOfRadius: r)
            dot.position = CGPoint(x: x, y: y)
            dot.fillColor = .white
            dot.strokeColor = .clear
            dot.alpha = CGFloat(0.12 + Double((i * 31) % 60) / 170)
            backgroundLayer.addChild(dot)
        }
    }

    private func render() {
        arenaLayer.removeAllChildren()
        hudLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        let cyan = NSColor(calibratedRed: modern ? 0.28 : 0.26, green: modern ? 0.94 : 0.82,
                           blue: 1, alpha: 1)
        let magenta = NSColor(calibratedRed: 1, green: 0.28, blue: 0.79, alpha: 1)

        if modern {
            let core = SKShapeNode(circleOfRadius: radius * 0.54)
            core.position = center
            core.fillColor = NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.26, alpha: 1)
            core.strokeColor = cyan.withAlphaComponent(0.2)
            core.glowWidth = 38
            arenaLayer.addChild(core)
        }
        for ring in 0...7 {
            let d = Double(ring) / 7
            let corners = (0..<rules.lanes).map { boundary(spoke: $0, depth: d) }
            if modern && ring > 0 {
                for i in 0..<rules.lanes {
                    let a = boundary(spoke: i, depth: Double(ring - 1) / 7)
                    let b = boundary(spoke: i + 1, depth: Double(ring - 1) / 7)
                    let c = boundary(spoke: i + 1, depth: d)
                    let e = boundary(spoke: i, depth: d)
                    let hue = i.isMultiple(of: 2) ? cyan : magenta
                    fill([a,b,c,e], color: hue, alpha: CGFloat(0.014 + d * 0.020), into: arenaLayer)
                }
            }
            line(corners, color: cyan, width: ring == 7 ? 2.4 : 0.95,
                 glow: ring == 7 ? (modern ? 9 : 3) : (modern ? 3 : 0),
                 alpha: CGFloat(0.19 + d * 0.59), close: true, into: arenaLayer)
        }
        for i in 0..<rules.lanes {
            line([boundary(spoke: i, depth: 0), boundary(spoke: i, depth: 1)],
                 color: cyan, width: modern ? 1.35 : 1.1,
                 glow: modern ? 4 : 0, alpha: modern ? 0.68 : 0.50, into: arenaLayer)
        }

        let rim = (0..<rules.lanes).map { boundary(spoke: $0, depth: 1.04) }
        line(rim, color: magenta, width: 1.3, glow: modern ? 7 : 1, alpha: 0.46,
             close: true, into: arenaLayer)

        for e in enemies {
            let position = point(lane: e.lane, depth: min(1.06, e.depth))
            let c = e.runner ? magenta : color(for: e.kind)
            let r: CGFloat = e.runner ? 14 : CGFloat(6 + e.depth * 11)
            let points: [CGPoint]
            if e.runner {
                points = [CGPoint(x: position.x-r, y: position.y-r),
                          CGPoint(x: position.x+r, y: position.y+r),
                          CGPoint(x: position.x+r, y: position.y-r),
                          CGPoint(x: position.x-r, y: position.y+r)]
                line(Array(points.prefix(2)), color: c, width: 3, glow: 5, into: arenaLayer)
                line(Array(points.suffix(2)), color: c, width: 3, glow: 5, into: arenaLayer)
            } else {
                switch e.kind {
                case .crawler:
                    points = [CGPoint(x: position.x, y: position.y+r),
                              CGPoint(x: position.x+r, y: position.y),
                              CGPoint(x: position.x, y: position.y-r),
                              CGPoint(x: position.x-r, y: position.y)]
                case .flipper:
                    points = [CGPoint(x: position.x-r, y: position.y+r),
                              CGPoint(x: position.x, y: position.y-r),
                              CGPoint(x: position.x+r, y: position.y+r),
                              CGPoint(x: position.x, y: position.y+r*0.3)]
                case .armored:
                    points = (0..<6).map { i in
                        let a = Double(i) * 2 * Double.pi / 6
                        return CGPoint(x: position.x + r * CGFloat(cos(a)),
                                       y: position.y + r * CGFloat(sin(a)))
                    }
                }
                fill(points, color: c, alpha: modern ? 0.24 : 0.12, into: arenaLayer)
                line(points, color: c, width: e.kind == .armored ? 2.7 : 2,
                     glow: modern ? 7 : 2, close: true, into: arenaLayer)
                if e.hp > 1 {
                    let inner = points.map { CGPoint(x: position.x + ($0.x-position.x)*0.52,
                                                    y: position.y + ($0.y-position.y)*0.52) }
                    line(inner, color: .white, width: 1.2, close: true, into: arenaLayer)
                }
            }
        }

        for shot in shots {
            let p = point(lane: shot.lane, depth: shot.depth)
            let q = point(lane: shot.lane, depth: min(1, shot.depth + 0.055))
            line([p,q], color: .white, width: modern ? 4 : 2.6,
                 glow: modern ? 11 : 4, into: arenaLayer)
        }

        let invulnVisible = invulnerable > 0 && Int(gameTime * 12).isMultiple(of: 2)
        if !invulnVisible || phase == .ready {
            let tip = point(lane: lane, depth: 0.995)
            let left = boundary(spoke: lane, depth: 1.14)
            let right = boundary(spoke: lane + 1, depth: 1.14)
            let tail = point(lane: lane, depth: 1.10)
            fill([tip, left, tail, right], color: magenta, alpha: modern ? 0.26 : 0.07, into: arenaLayer)
            line([tip, left, tail, right], color: .white, width: 2.4,
                 glow: modern ? 12 : 4, close: true, into: arenaLayer)
            line([tip, tail], color: magenta, width: 2, glow: 5, into: arenaLayer)
        }

        if pulseVisual > 0 {
            let outerDepth = min(1.1, 0.20 + (1.0 - pulseVisual) * 1.2)
            let ringPoints = (0..<rules.lanes).map { boundary(spoke: $0, depth: outerDepth) }
            line(ringPoints, color: .systemPink, width: CGFloat(2 + pulseVisual * 8),
                 glow: CGFloat(10 + pulseVisual * 30), alpha: CGFloat(pulseVisual),
                 close: true, into: arenaLayer)
        }

        for spark in sparks {
            let r = CGFloat(2.5 * (1 - spark.age / 0.45))
            let dot = SKShapeNode(circleOfRadius: max(0.2, r))
            dot.position = spark.position
            dot.fillColor = spark.color
            dot.strokeColor = .clear
            dot.glowWidth = modern ? 5 : 1
            dot.alpha = CGFloat(max(0, 1 - spark.age / 0.45))
            arenaLayer.addChild(dot)
        }

        drawHUD(cyan: cyan, magenta: magenta)
        if flash > 0 {
            let rect = SKShapeNode(rectOf: size)
            rect.position = CGPoint(x: size.width / 2, y: size.height / 2)
            rect.fillColor = .systemRed
            rect.strokeColor = .clear
            rect.alpha = CGFloat(flash * 0.18)
            overlayLayer.addChild(rect)
        }
        if phase != .playing { drawOverlay(cyan: cyan) }
        else if announcement > 0 {
            label("WAVE \(wave)", x: center.x, y: size.height * 0.92, size: 24,
                  color: .white, align: .center, into: overlayLayer, bold: true)
        }
    }

    private func drawHUD(cyan: NSColor, magenta: NSColor) {
        let tx = size.width * 0.765
        let right = size.width * 0.97
        let top = size.height * 0.89
        if modern {
            let panel = SKShapeNode(rect: CGRect(x: tx - 25, y: size.height * 0.12,
                                                  width: right - tx + 38,
                                                  height: size.height * 0.82),
                                    cornerRadius: 15)
            panel.fillColor = NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.16, alpha: 0.88)
            panel.strokeColor = cyan.withAlphaComponent(0.24)
            panel.lineWidth = 1
            hudLayer.addChild(panel)
        }
        line([CGPoint(x: tx-24, y: size.height*0.13),
              CGPoint(x: tx-24, y: size.height*0.93)], color: cyan, width: 1,
             alpha: 0.25, into: hudLayer)
        label("VECTOR / VORTEX", x: tx, y: top, size: 15,
              color: cyan, into: hudLayer, bold: true)
        label("TACTICAL TELEMETRY", x: tx, y: top-25, size: 9,
              color: .lightGray, into: hudLayer)
        label("SCORE", x: tx, y: top-77, size: 10, color: .gray, into: hudLayer)
        label(String(format: "%07d", score), x: right, y: top-113, size: 31,
              color: .white, align: .right, into: hudLayer, bold: true)
        label("HI \(String(format: "%07d", VortexStore.highScore))",
              x: right, y: top-143, size: 11, color: cyan,
              align: .right, into: hudLayer)
        label("WAVE", x: tx, y: top-194, size: 10, color: .gray, into: hudLayer)
        label(String(format: "%02d", wave), x: right, y: top-198, size: 24,
              color: .white, align: .right, into: hudLayer, bold: true)
        label("LIVES", x: tx, y: top-237, size: 10, color: .gray, into: hudLayer)
        label("\(lives)", x: right, y: top-241, size: 23, color: magenta,
              align: .right, into: hudLayer, bold: true)
        label("AMMO RESERVE", x: tx, y: top-287, size: 10,
              color: .gray, into: hudLayer)
        label("\(ammo) / 500", x: right, y: top-289, size: 14,
              color: cyan, align: .right, into: hudLayer, bold: true)
        let barWidth = right - tx
        fill([CGPoint(x:tx,y:top-314), CGPoint(x:right,y:top-314),
              CGPoint(x:right,y:top-321), CGPoint(x:tx,y:top-321)],
             color: .darkGray, alpha: 0.5, into: hudLayer)
        fill([CGPoint(x:tx,y:top-314), CGPoint(x:tx+barWidth*CGFloat(ammo)/500,y:top-314),
              CGPoint(x:tx+barWidth*CGFloat(ammo)/500,y:top-321),
              CGPoint(x:tx,y:top-321)],
             color: cyan, alpha: 0.8, into: hudLayer)
        let recharge = ammo == 500 ? "FULL" : shotIdle < 5 ?
            String(format:"REFILL IN %.1FS", max(0, 5-shotIdle)) : "RECHARGING"
        label(recharge, x: right, y: top-342, size: 10, color: .gray,
              align: .right, into: hudLayer)
        label("SHOT ACCURACY", x: tx, y: top-382, size: 10, color: .gray, into: hudLayer)
        let accuracy = shotsFired == 0 ? 0 : Double(shotsHit) / Double(shotsFired) * 100
        label(String(format:"%.0f%%", accuracy), x: right, y: top-385, size: 19,
              color: .white, align: .right, into: hudLayer, bold: true)
        label("\(shotsHit) HITS  /  \(shotsFired) FIRED",
              x: right, y: top-410, size: 9, color: .gray,
              align: .right, into: hudLayer)
        label("PULSE", x: tx, y: top-455, size: 10, color: .gray, into: hudLayer)
        label(!rules.pulse ? "DISABLED" : pulseAvailable ? "READY" : "SPENT",
              x: right, y: top-458, size: 16,
              color: pulseAvailable ? .systemGreen : .systemOrange,
              align: .right, into: hudLayer, bold: true)
        label(modern ? "MODERN / DEPTH" : "CLASSIC / VECTOR", x: right,
              y: size.height * 0.145, size: 10, color: cyan,
              align: .right, into: hudLayer)
        label("← → / A D  MOVE     SPACE  FIRE", x: 25, y: 38,
              size: 10, color: .lightGray, into: hudLayer)
        label("SHIFT  PULSE    P  PAUSE    ENTER  START", x: 25, y: 20,
              size: 9, color: .gray, into: hudLayer)
    }

    private func drawOverlay(cyan: NSColor) {
        let heading: String
        let detail: String
        switch phase {
        case .ready:
            heading = "VECTOR VORTEX"
            detail = "PRESS RETURN TO ENTER THE GRID"
        case .paused:
            heading = "PAUSED"
            detail = "PRESS P OR RETURN TO RESUME"
        case .gameOver:
            heading = "GAME OVER"
            detail = "PRESS RETURN TO RESTART"
        case .playing: return
        }
        let panel = SKShapeNode(rect: CGRect(x: center.x-222, y: center.y-74,
                                              width: 444, height: 148), cornerRadius: 15)
        panel.fillColor = NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.06, alpha: 0.94)
        panel.strokeColor = cyan
        panel.lineWidth = 1.5
        panel.glowWidth = modern ? 10 : 2
        overlayLayer.addChild(panel)
        label(heading, x: center.x, y: center.y+21, size: 29,
              color: .white, align: .center, into: overlayLayer, bold: true)
        label(detail, x: center.x, y: center.y-30, size: 11,
              color: cyan, align: .center, into: overlayLayer)
    }

    func feedback() -> String {
        "Vector Vortex | \(difficulty) | \(modern ? "Modern" : "Classic") | \(phase) | Wave \(wave) | Score \(score) | Lives \(lives) | Shots \(shotsFired) | Hits \(shotsHit) | Enemies \(enemies.count)"
    }
}
