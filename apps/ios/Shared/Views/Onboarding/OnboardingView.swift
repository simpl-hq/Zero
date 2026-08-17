import SwiftUI

struct OnboardingView: View {
    var onboarding: OnboardingStage

    var body: some View {
        NavigationView {
            switch onboarding {
            case .step1_ZeroInfo:
                ZeroInfo(onboarding: true)
                    .modifier(ThemedBackground())
            case .step2_CreateProfile:
                CreateFirstProfile()
                    .modifier(ThemedBackground())
            case .step3_CreateZeroAddress:
                CreateZeroAddress()
            case .step3_ChooseServerOperators,
                .step4_SetNotificationsMode:
                YourNetworkView()
                    .navigationBarBackButtonHidden(true)
                    .modifier(ThemedBackground())
            case .step4_NetworkCommitments:
                OnboardingConditionsView(selectedOperatorIds: Set(ChatModel.shared.conditions.serverOperators.filter { $0.enabled }.map { $0.operatorId }))
                    .navigationBarBackButtonHidden(true)
                    .modifier(ThemedBackground())
            case .onboardingComplete: EmptyView()
            }
        }
    }
}

func onboardingButtonPlaceholder() -> some View {
    Spacer().frame(height: 40)
}

enum OnboardingStage: String, Identifiable {
    case step1_ZeroInfo
    case step2_CreateProfile
    case step3_CreateZeroAddress
    case step3_ChooseServerOperators
    case step4_SetNotificationsMode
    case step4_NetworkCommitments
    case onboardingComplete

    public var id: Self { self }
}

struct OnboardingStepsView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(onboarding: .step1_ZeroInfo)
    }
}
