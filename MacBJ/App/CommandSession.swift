import Observation

@Observable
final class CommandSession {
    var command = ""
    var output = ""
    var isRunning = false
    var isCancelling = false
    var isPresented = false

    @ObservationIgnored
    private var task: Task<Void, Never>?
    @ObservationIgnored
    private var handle: ShellHandle?
    @ObservationIgnored
    private var generation = 0

    func begin(_ command: String, handle: ShellHandle) -> Int {
        task?.cancel()
        self.handle?.cancel()
        generation += 1
        self.handle = handle
        self.command = command
        output = ""
        isCancelling = false
        isRunning = true
        isPresented = true
        return generation
    }

    func isCurrent(_ token: Int) -> Bool {
        token == generation
    }

    func track(_ task: Task<Void, Never>) {
        self.task = task
    }

    func append(_ text: String) {
        guard !text.isEmpty else { return }
        output += text
        if output.count > 200_000 {
            output = String(output.suffix(160_000))
        }
    }

    func finish(_ token: Int) {
        guard token == generation else { return }
        isRunning = false
        isCancelling = false
        handle = nil
    }

    func cancel() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        append("\n正在取消…\n")
        handle?.cancel()
        task?.cancel()
    }

    func dismiss() {
        guard !isRunning else { return }
        isPresented = false
    }
}
