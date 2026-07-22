// Verifies Vhrase's production workflow phases and their public transition guards.

@main
struct StatusFlowCheck {
    static func main() {
        precondition(AppStatus.idle.canStartRecording)
        precondition(AppStatus.completed.canStartRecording)
        precondition(AppStatus.failed("x").canStartRecording)
        precondition(!AppStatus.preparing.canStartRecording)
        precondition(!AppStatus.recording.canStartRecording)
        precondition(!AppStatus.transcribing.canStartRecording)
        precondition(!AppStatus.adjusting.canStartRecording)
        precondition(!AppStatus.idle.showsWorkflowPopup)
        precondition(AppStatus.preparing.showsWorkflowPopup)
        precondition(AppStatus.recording.showsWorkflowPopup)
        precondition(AppStatus.transcribing.showsWorkflowPopup)
        precondition(AppStatus.adjusting.showsWorkflowPopup)
        precondition(AppStatus.completed.showsWorkflowPopup)
        precondition(AppStatus.failed("x").showsWorkflowPopup)
        precondition(AppStatus.transcribing.isProcessing)
        precondition(AppStatus.adjusting.isProcessing)
        precondition(!AppStatus.preparing.isProcessing)
        print("status flow ok")
    }
}
