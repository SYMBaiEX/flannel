//
//  ProviderAccessModePresentation.swift
//  flannel
//

extension ProviderAccessMode {
    var icon: String {
        switch self {
        case .localServer:
            "desktopcomputer"
        case .apiKey:
            "key"
        case .subscriptionCLI:
            "terminal"
        case .openAICompatible:
            "arrow.left.arrow.right"
        case .anthropicCompatible:
            "text.bubble"
        case .aiSDKBridge:
            "shippingbox"
        }
    }
}
