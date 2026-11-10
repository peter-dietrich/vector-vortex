import AppKit
import SpriteKit
import SwiftUI

@main
struct VectorVortexApp: App {
    var body: some Scene {
        WindowGroup("Vector Vortex") {
            VortexWindow()
                .frame(minWidth: 950, minHeight: 660)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1250, height: 805)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class VortexSession: ObservableObject {
    @Published var modern = false
    @Published var difficulty = "Veteran"
    @Published var soundOn = true
    @Published var activePreset: VortexPreset?
    let scene = VortexScene(size: CGSize(width: 1250, height: 760))

    func applySettings() {
        scene.modern = modern
        scene.soundOn = soundOn
    }

    func newGame() {
        applySettings()
        scene.start(difficulty: difficulty, custom: activePreset?.rules)
    }

    func usePreset(_ preset: VortexPreset?) {
        activePreset = preset
        newGame()
    }

    func load(_ save: VortexSave) {
        modern = save.snapshot.modern
        difficulty = ["Cadet", "Veteran", "Ace"].contains(save.snapshot.difficulty)
            ? save.snapshot.difficulty : "Veteran"
        activePreset = nil
        scene.restore(save.snapshot)
        applySettings()
    }
}

struct VortexWindow: View {
    @StateObject private var session = VortexSession()
    @State private var showRules = false
    @State private var showSaves = false
    @State private var showNotice = false
    @State private var noticeText = ""

    private let cyan = Color(red: 0.3, green: 0.9, blue: 1)
    private let magenta = Color(red: 1, green: 0.3, blue: 0.76)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                HStack(spacing: 6) {
                    Image(systemName: "hurricane")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(magenta)
                    Text("VECTOR VORTEX")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .tracking(2.0)
                }
                Spacer(minLength: 0)
                Picker("Display", selection: $session.modern) {
                    Text("Classic").tag(false)
                    Text("Modern").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)
                Picker("Difficulty", selection: $session.difficulty) {
                    ForEach(["Cadet", "Veteran", "Ace"], id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .frame(width: 121)
                .disabled(session.activePreset != nil)
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help(session.activePreset?.name ?? "Custom game rules")
                Button {
                    session.soundOn.toggle()
                } label: {
                    Image(systemName: session.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .help("Toggle synthesized arcade sounds")
                Button {
                    if let snap = session.scene.snapshot() {
                        VortexStore.saveGame(snap)
                        noticeText = "Game saved locally. Choose Load to resume it later."
                    } else {
                        noticeText = "Start a game before saving."
                    }
                    showNotice = true
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Button {
                    showSaves = true
                } label: {
                    Label("Load", systemImage: "folder")
                }
                Button {
                    session.newGame()
                } label: {
                    Label("New Game", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(cyan)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 17)
            .frame(height: 60)
            .background(Color(red: 0.042, green: 0.055, blue: 0.09))

            VortexGameView(scene: session.scene)
                .background(.black)
                .overlay(alignment: .topLeading) {
                    if let preset = session.activePreset {
                        Text("CUSTOM / \(preset.name.uppercased())")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(magenta)
                            .padding(.leading, 20)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear { session.applySettings() }
        .onChange(of: session.modern) { _ in session.applySettings() }
        .onChange(of: session.soundOn) { _ in session.applySettings() }
        .sheet(isPresented: $showRules) {
            VortexRuleEditor(difficulty: session.difficulty, active: session.activePreset) {
                session.usePreset($0)
            }
        }
        .sheet(isPresented: $showSaves) {
            VortexLoadSheet { save in
                session.load(save)
            }
        }
        .alert("VECTOR VORTEX", isPresented: $showNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeText)
        }
        .commandsRemoved()
    }
}

private extension View {
    // Reserves the default app menu for system commands; gameplay uses the in-window toolbar.
    func commandsRemoved() -> some View { self }
}

struct VortexGameView: NSViewRepresentable {
    let scene: VortexScene

    func makeNSView(context: Context) -> VortexKeyView {
        let view = VortexKeyView()
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        view.preferredFramesPerSecond = 60
        view.game = scene
        view.presentScene(scene)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: VortexKeyView, context: Context) {
        if view.scene !== scene {
            view.game = scene
            view.presentScene(scene)
        }
    }
}

final class VortexKeyView: SKView {
    weak var game: VortexScene?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        game?.press(event.keyCode, repeatKey: event.isARepeat, modifiers: event.modifierFlags)
    }

    override func keyUp(with event: NSEvent) {
        game?.release(event.keyCode)
    }

    override func flagsChanged(with event: NSEvent) {
        game?.shiftChanged(event.modifierFlags.contains(.shift))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
        }
    }
}

private struct VortexRuleEditor: View {
    let difficulty: String
    let active: VortexPreset?
    let apply: (VortexPreset?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presets: [VortexPreset] = []
    @State private var selectedID: UUID?
    @State private var name = "My Vortex"
    @State private var rules = VortexRules()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CUSTOM GAME")
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    Text("Tune the arena, save a preset, and launch your own rules.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "hurricane")
                    .font(.system(size: 29))
                    .foregroundStyle(.pink)
            }
            HStack(spacing: 9) {
                Picker("Saved preset", selection: $selectedID) {
                    Text("New preset").tag(nil as UUID?)
                    ForEach(presets) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                .onChange(of: selectedID) { id in
                    guard let preset = presets.first(where: { $0.id == id }) else { return }
                    name = preset.name
                    rules = preset.rules
                }
                Button("New") {
                    selectedID = nil
                    name = "My Vortex"
                    rules = VortexRules.standard(difficulty)
                }
            }
            TextField("Preset name", text: $name)
            Form {
                Section("Arena") {
                    Stepper("Lanes: \(rules.lanes)", value: $rules.lanes, in: 8...20)
                    Stepper("Starting lives: \(rules.startingLives)",
                            value: $rules.startingLives, in: 1...12)
                    SliderRow(title: "Move interval", value: $rules.moveInterval,
                              range: 0.055...0.25, step: 0.005, suffix: "s")
                }
                Section("Weapons") {
                    SliderRow(title: "Shot interval", value: $rules.fireInterval,
                              range: 0.07...0.45, step: 0.01, suffix: "s")
                    Toggle("Enable one pulse per wave", isOn: $rules.pulse)
                    Text("500 rounds; automatic recharge after a 5-second firing pause.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Enemies") {
                    Stepper("First wave: \(rules.firstWaveEnemies)",
                            value: $rules.firstWaveEnemies, in: 2...30)
                    Stepper("Additional per wave: \(rules.waveGrowth)",
                            value: $rules.waveGrowth, in: 0...6)
                    SliderRow(title: "Enemy speed", value: $rules.enemySpeed,
                              range: 0.35...3, step: 0.05, suffix: "×")
                    Toggle("Flippers switch lanes", isOn: $rules.flippers)
                    Toggle("Armored enemies require two hits", isOn: $rules.armored)
                    Toggle("Escaped enemies run along the rim", isOn: $rules.runners)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Delete Preset", role: .destructive) {
                    guard let id = selectedID else { return }
                    VortexStore.removePreset(id)
                    presets = VortexStore.presets()
                    selectedID = nil
                    name = "My Vortex"
                    rules = VortexRules.standard(difficulty)
                    if active?.id == id { apply(nil) }
                }
                .disabled(selectedID == nil)
                Spacer()
                Button("Built-in Difficulty") {
                    apply(nil)
                    dismiss()
                }
                Button("Save & Start") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let p = VortexPreset(id: selectedID ?? UUID(),
                                         name: trimmed.isEmpty ? "My Vortex" : trimmed,
                                         rules: rules.validated())
                    VortexStore.savePreset(p)
                    apply(p)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 650, height: 710)
        .onAppear {
            presets = VortexStore.presets()
            if let active {
                selectedID = active.id
                name = active.name
                rules = active.rules
            } else {
                rules = VortexRules.standard(difficulty)
            }
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text(String(format: "%.2f%@", value, suffix))
                .monospacedDigit()
                .frame(width: 77, alignment: .trailing)
        }
    }
}

private struct VortexLoadSheet: View {
    let load: (VortexSave) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saves: [VortexSave] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("LOAD SAVED GAME")
                .font(.system(size: 23, weight: .heavy, design: .monospaced))
            Text("Up to 12 locally saved sessions. Resuming does not delete a slot.")
                .foregroundStyle(.secondary)
            if saves.isEmpty {
                ContentUnavailableView("No Saves Yet", systemImage: "externaldrive",
                                       description: Text("Start a game and select Save."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(saves) { save in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(save.title).font(.system(.body, design: .monospaced).bold())
                                Text(save.snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Resume") {
                                load(save)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            Button(role: .destructive) {
                                VortexStore.deleteSave(save.id)
                                saves = VortexStore.saves()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 580, height: 470)
        .onAppear { saves = VortexStore.saves() }
    }
}
