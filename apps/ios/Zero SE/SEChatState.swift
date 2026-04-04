import SwiftUI
import Zero

class SEChatState {
    static let shared = SEChatState()
    private var value_ = seStateGroupDefault.get()

    var value: SEState {
        value_
    }

    func set(_ state: SEState) {
        seStateGroupDefault.set(state)
        sendSEState(state)
        value_ = state
    }
}

func waitForOtherProcessesToSuspend() async {
    let startTime = CFAbsoluteTimeGetCurrent()
    while CFAbsoluteTimeGetCurrent() - startTime < 2 {
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
        if appStateGroupDefault.get() == .suspended &&
           nseStateGroupDefault.get() == .suspended {
            break
        }
    }
}
