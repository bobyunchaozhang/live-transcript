import Foundation

enum CaptureError: LocalizedError {
    case microphonePermission
    case microphoneUnavailable
    case microphoneInterrupted
    case audioSystem(action: String, status: OSStatus)
    case audioFormat
    case audioBacklog
    case speechUnavailable
    case speechAssetsMissing

    var errorDescription: String? {
        switch self {
        case .microphonePermission: "请在系统设置中允许「会听」访问麦克风，然后重新开始。"
        case .microphoneUnavailable: "找不到可用的麦克风。"
        case .microphoneInterrupted: "麦克风已断开或被系统中断。"
        case .audioSystem(let action, let status): "\(action)失败（\(status)）。请检查系统音频录制权限，再重新开始。"
        case .audioFormat: "当前音频格式无法转换为语音识别所需的格式。"
        case .audioBacklog: "音频处理未能跟上实时输入，转写已停止。"
        case .speechUnavailable: "无法启动本地中英文识别。"
        case .speechAssetsMissing: "会听的中英文识别文件不完整。请重新构建或使用完整的 App。"
        }
    }
}
