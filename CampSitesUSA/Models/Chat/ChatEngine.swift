import Foundation
import Observation
import OperatorLLM

/// One line in the "Ask ezcamp" conversation.
struct ChatItem: Identifiable, Equatable {
    enum Kind: Equatable { case user, assistant, activity, error }
    let id = UUID()
    var kind: Kind
    var text: String
    /// Campsites this answer is about (shown as tappable chips and highlighted on the map).
    var siteIDs: [String] = []
    /// A trip this answer created.
    var tripCreated: Bool = false
}

/// Runs the conversation: picks the client from Settings (any provider key, or Apple's on-device
/// model), drives the tool loop (OperatorLLM's AgentLoop for cloud models, Apple's session for
/// on-device), and keeps a transcript so follow-ups have context.
@MainActor
@Observable
final class ChatEngine {
    private(set) var items: [ChatItem] = []
    private(set) var running = false
    /// Sites the latest answer is about, for the map.
    private(set) var highlighted: [String] = []
    private(set) var lastTrip: Trip?

    @ObservationIgnored private var history: [LLMMessage] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored let tools: ChatTools

    init(tools: ChatTools) { self.tools = tools }

    static let instructions = """
    You are ezcamp, a camping assistant for the United States, inside an iPhone app with a map.
    Use the tools for every fact about campsites, land rules, weather, safety, wildlife, licenses and activities, and only name campsites a tool returned. Never invent a campsite, a rule or a number.
    Say where an answer comes from in a few words (for example "per the National Weather Service").
    Keep answers short and practical: a few sentences or a short list. Use miles and °F.
    For "near here" use near = "map"; for "near me" use near = "me".
    Safety and legality are guidance, not guarantees: mention checking posted rules, closures and fire restrictions when it matters.
    Plan or save a trip only when the person asks for it.
    """

    func send(_ text: String, settings: AISettings) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !running else { return }
        items.append(ChatItem(kind: .user, text: prompt))
        running = true
        tools.resetTurn()
        let choice = settings.model(for: .chat)
        task = Task {
            defer { running = false; task = nil }
            if choice.isOnDevice { await runOnDevice(prompt) } else { await runCloud(prompt, choice: choice, settings: settings) }
            highlighted = tools.mentioned
            lastTrip = tools.createdTrip
        }
    }

    func stop() {
        task?.cancel()
        running = false
    }

    func clear() {
        stop()
        items = []
        history = []
        highlighted = []
        lastTrip = nil
    }

    // MARK: Cloud (any provider key)

    private func runCloud(_ prompt: String, choice: ModelChoice, settings: AISettings) async {
        guard let provider = choice.provider, let key = APIKeyStore.key(for: provider), !key.isEmpty else {
            items.append(ChatItem(kind: .error, text: "Add an API key in Settings › AI, or switch Ask ezcamp to the on-device model."))
            return
        }
        let client: any LLMToolClient
        if provider == .anthropic {
            client = AnthropicMessagesClient(apiKey: key)
        } else {
            client = OpenAICompatibleClient(baseURL: settings.baseURL(for: provider), apiKey: key,
                                            referer: "https://harikanth.site/ezcamp", appTitle: "ezcamp")
        }
        if history.isEmpty { history = [LLMMessage(.system, Self.instructions)] }
        history.append(LLMMessage(.user, prompt))
        let answer = ChatItem(kind: .assistant, text: "")
        items.append(answer)
        let model = choice.modelID
        let tools = self.tools
        do {
            let outcome = try await AgentLoop.run(
                messages: history,
                tools: ChatTools.specs,
                maxRounds: 6,
                round: { messages, specs in client.streamWithTools(messages: messages, model: model, tools: specs) },
                execute: { call in await tools.run(call) },
                parallelSafe: ChatTools.parallelSafe,
                onText: { [weak self] delta in self?.appendToAnswer(answer.id, delta) },
                onToolCall: { [weak self] call in self?.noteTool(call.name) })
            history.append(contentsOf: outcome.appended)
            finish(answer.id)
        } catch {
            history.removeLast()   // the question that failed, so a retry starts clean
            fail(answer.id, error)
        }
    }

    // MARK: On-device (Apple Intelligence)

    private func runOnDevice(_ prompt: String) async {
        guard OnDeviceLLM.isAvailable else {
            items.append(ChatItem(kind: .error, text: "Apple's on-device model isn't available on this iPhone. Add a key for Claude, OpenAI or another provider in Settings › AI."))
            return
        }
        // The on-device window is small, so carry only the last few exchanges as context.
        let recent = items.filter { $0.kind == .user || $0.kind == .assistant }.suffix(6).dropLast()
            .map { ($0.kind == .user ? "Person: " : "ezcamp: ") + $0.text }.joined(separator: "\n")
        let full = recent.isEmpty ? prompt : "Conversation so far:\n\(recent)\n\nPerson: \(prompt)"
        let answer = ChatItem(kind: .assistant, text: "")
        items.append(answer)
        let tools = self.tools
        let deviceTools = OnDeviceToolBridge.tools(ChatTools.specs) { call in
            await MainActor.run { [weak self] in self?.noteTool(call.name) }
            return await tools.run(call)
        }
        do {
            for try await delta in OnDeviceLLM(instructions: Self.instructions).streamText(prompt: full, tools: deviceTools) {
                appendToAnswer(answer.id, delta)
            }
            finish(answer.id)
        } catch is CancellationError {
            fail(answer.id, CancellationError())
        } catch let error as LLMError {
            fail(answer.id, error)
        } catch {
            // Foundation Models errors read like crash codes; say what to do instead.
            items.removeAll { $0.id == answer.id && $0.text.isEmpty }
            items.append(ChatItem(kind: .error, text: "Apple's on-device model couldn't answer that here. Try a shorter question, or add a key for Claude, OpenAI or another provider in Settings › AI for fuller answers."))
        }
    }

    // MARK: Transcript updates

    private func appendToAnswer(_ id: UUID, _ delta: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].text += delta
    }

    private func noteTool(_ name: String) {
        let line: String = switch name {
        case "search_campsites": "Searching campsites…"
        case "campsite_details": "Reading the campsite details…"
        case "can_i_camp_here": "Checking who manages the land…"
        case "night_conditions": "Checking tonight's weather, smoke and fires…"
        case "safety": "Looking at safety reports and nearest help…"
        case "fishing_hunting": "Checking fish, game and license rules…"
        case "things_to_do": "Finding things to do nearby…"
        case "plan_trip": "Planning the route and camps…"
        default: "Looking that up…"
        }
        // Activity lines sit just above the answer they feed.
        let at = items.lastIndex(where: { $0.kind == .assistant }) ?? items.endIndex
        if items.indices.contains(at - 1), items[at - 1].kind == .activity, items[at - 1].text == line { return }
        items.insert(ChatItem(kind: .activity, text: line), at: at)
    }

    private func finish(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].siteIDs = Array(tools.mentioned.prefix(8))
        items[i].tripCreated = tools.createdTrip != nil
        if items[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items[i].text = "I couldn't put an answer together. Try asking another way."
        }
    }

    private func fail(_ id: UUID, _ error: Error) {
        items.removeAll { $0.id == id && $0.text.isEmpty }
        if error is CancellationError || (error as? LLMError).map({ if case .cancelled = $0 { true } else { false } }) == true { return }
        items.append(ChatItem(kind: .error, text: error.localizedDescription))
    }
}
