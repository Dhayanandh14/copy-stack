import Foundation
let what = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "panel"
let name = what == "settings" ? "local.clipstack.openSettings" : "local.clipstack.openPanel"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
print("sent \(name)")
