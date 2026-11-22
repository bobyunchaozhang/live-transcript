import SwiftUI

struct ConversationPalette {
    let backdrop: Color
    let board: Color
    let boardShadow: Color
    let microphone: Color
    let application: Color
    let microphoneLabel: Color
    let applicationLabel: Color

    init(_ mode: ColorScheme) {
        switch mode {
        case .dark:
            backdrop = Color(red: 0.19, green: 0.23, blue: 0.27)
            board = Color(white: 0.12)
            boardShadow = .black.opacity(0.20)
            microphone = Color(red: 0.15, green: 0.38, blue: 0.35)
            application = Color(red: 0.31, green: 0.26, blue: 0.53)
            microphoneLabel = Color(red: 0.57, green: 0.83, blue: 0.77)
            applicationLabel = Color(red: 0.76, green: 0.71, blue: 0.99)
        default:
            backdrop = Color(red: 0.86, green: 0.895, blue: 0.925)
            board = .white
            boardShadow = Color(red: 0.18, green: 0.27, blue: 0.35).opacity(0.09)
            microphone = Color(red: 0.66, green: 0.90, blue: 0.83)
            application = Color(red: 0.84, green: 0.79, blue: 0.98)
            microphoneLabel = Color(red: 0.13, green: 0.37, blue: 0.34)
            applicationLabel = Color(red: 0.32, green: 0.25, blue: 0.54)
        }
    }
}
