// 跨端本地通知/闹钟服务。
// io(Android/iOS/Linux/macOS/Windows): 使用 flutter_local_notifications
// web: 浏览器 Notifications API（授权 + 网页内定时提醒；关闭页面不保证触发）
// 其余目标: 空实现
export 'local_notifications_stub.dart'
    if (dart.library.io) 'local_notifications_io.dart'
    if (dart.library.js_interop) 'local_notifications_web.dart';
