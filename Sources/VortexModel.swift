import Foundation

struct VortexRules: Codable, Equatable {
    var lanes: Int = 14
    var startingLives: Int = 3
    var firstWaveEnemies: Int = 8
    var waveGrowth: Int = 2
    var enemySpeed: Double = 1
    var fireInterval: Double = 0.13
    var moveInterval: Double = 0.095
    var flippers: Bool = true
    var armored: Bool = true
    var runners: Bool = true
    var pulse: Bool = true

    static func standard(_ difficulty: String) -> VortexRules {
        var r = VortexRules()
        switch difficulty {
        case "Cadet":
            r.startingLives = 5
            r.firstWaveEnemies = 5
            r.enemySpeed = 0.7
        case "Ace":
            r.startingLives = 2
            r.firstWaveEnemies = 11
            r.waveGrowth = 3
            r.enemySpeed = 1.45
            r.fireInterval = 0.17
        default: break
        }
        return r
    }

    func validated() -> VortexRules {
        var r = self
        r.lanes = max(8, min(20, r.lanes))
        r.startingLives = max(1, min(12, r.startingLives))
        r.firstWaveEnemies = max(2, min(30, r.firstWaveEnemies))
        r.waveGrowth = max(0, min(6, r.waveGrowth))
        r.enemySpeed = max(0.35, min(3.0, r.enemySpeed))
        r.fireInterval = max(0.07, min(0.45, r.fireInterval))
        r.moveInterval = max(0.055, min(0.25, r.moveInterval))
        return r
    }

    func count(for wave: Int) -> Int {
        min(50, firstWaveEnemies + max(0, wave - 1) * waveGrowth)
    }
}

enum VortexEnemyKind: String, Codable {
    case crawler, flipper, armored
}

struct VortexEnemy: Codable, Identifiable {
    var id: UUID = UUID()
    var lane: Int
    var depth: Double
    var kind: VortexEnemyKind
    var hp: Int
    var age: Double = 0
    var runner: Bool = false
    var direction: Int = 1
}

struct VortexShot: Codable, Identifiable {
    var id: UUID = UUID()
    var lane: Int
    var depth: Double
}

struct VortexSnapshot: Codable {
    var version: Int = 1
    var savedAt: Date = Date()
    var difficulty: String
    var modern: Bool
    var rules: VortexRules
    var score: Int
    var lives: Int
    var wave: Int
    var lane: Int
    var spawnRemaining: Int
    var spawnClock: Double
    var spawnIndex: Int
    var pulseAvailable: Bool
    var ammo: Int
    var rechargeFraction: Double
    var shotIdle: Double
    var shotsFired: Int
    var shotsHit: Int
    var invulnerable: Double
    var gameTime: Double
    var enemies: [VortexEnemy]
    var shots: [VortexShot]
}

struct VortexPreset: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var rules: VortexRules
}

struct VortexSave: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var snapshot: VortexSnapshot
}

enum VortexStore {
    private static let presetsKey = "vectorVortex.presets.v1"
    private static let savesKey = "vectorVortex.saves.v1"
    private static let scoreKey = "vectorVortex.highscore.v1"

    private static func read<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return decoded
    }

    private static func write<T: Encodable>(_ values: [T], _ key: String) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func presets() -> [VortexPreset] { read(presetsKey) }

    static func preset(_ id: UUID?) -> VortexPreset? {
        guard let id else { return nil }
        return presets().first(where: { $0.id == id })
    }

    static func savePreset(_ item: VortexPreset) {
        var list = presets()
        let value = VortexPreset(id: item.id, name: item.name, rules: item.rules.validated())
        if let index = list.firstIndex(where: { $0.id == item.id }) { list[index] = value }
        else { list.append(value) }
        write(list, presetsKey)
    }

    static func removePreset(_ id: UUID) {
        write(presets().filter { $0.id != id }, presetsKey)
    }

    static func saves() -> [VortexSave] { read(savesKey) }

    static func saveGame(_ snapshot: VortexSnapshot) {
        var list = saves()
        list.insert(VortexSave(title: "WAVE \(snapshot.wave) · \(snapshot.score) PTS · \(snapshot.difficulty)",
                               snapshot: snapshot), at: 0)
        write(Array(list.prefix(12)), savesKey)
    }

    static func deleteSave(_ id: UUID) {
        write(saves().filter { $0.id != id }, savesKey)
    }

    static var highScore: Int {
        get { UserDefaults.standard.integer(forKey: scoreKey) }
        set { UserDefaults.standard.set(newValue, forKey: scoreKey) }
    }
}
