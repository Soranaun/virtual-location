import SwiftUI
import CoreLocation

/// This screen uses explicit WGS-84 input, avoiding unverified map-provider conversions.
struct PrecisionLocationView: View {
    @ObservedObject private var session = LocationSimulationSession.shared
    @AppStorage("precision.pendingRecovery") private var pendingRecovery = false
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var distance = "5"
    @State private var bearing = "90"
    @State private var anchor: PrecisionGeodesy.Point?
    @State private var target: PrecisionGeodesy.Point?
    @State private var busy = false
    @State private var status = "尚未开始模拟"

    private var input: PrecisionGeodesy.Point? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let p = PrecisionGeodesy.Point(latitude: lat, longitude: lon)
        return p.isValid ? p : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("连接准备") {
                    Text("首次请到设置导入本机配对文件，连接专用回环 VPN，并等待开发者镜像准备完成。")
                        .font(.footnote)
                    NavigationLink("打开连接与配对设置") { SettingsView() }
                }
                Section("WGS-84 坐标") {
                    TextField("纬度 −90…90", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("经度 −180…180", text: $longitude).keyboardType(.numbersAndPunctuation)
                    Button("固定为 A 点") { anchor = input; target = input }
                        .disabled(input == nil || busy)
                    if let anchor { Text("A：\(formatted(anchor))").font(.caption).textSelection(.enabled) }
                    Text("请输入可靠的 WGS-84 坐标。地图选点、GCJ-02 / BD-09 坐标不能直接用于米级验证。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("相对 A 点偏移") {
                    TextField("距离（0–100000 米）", text: $distance).keyboardType(.decimalPad)
                    HStack {
                        ForEach([1, 5, 50, 500], id: \.self) { n in
                            Button("\(n)m") { distance = String(n); calculate() }.buttonStyle(.bordered)
                        }
                    }
                    TextField("方位角：北 0° / 东 90° / 南 180° / 西 270°", text: $bearing)
                        .keyboardType(.numbersAndPunctuation)
                    Button("计算目标点") { calculate() }.disabled(anchor == nil || busy)
                    if let target { Text("目标：\(formatted(target))").font(.caption).textSelection(.enabled) }
                    Text("偏移始终从固定 A 点计算，不累积、不加入随机漂移；坐标计算精度不代表第三方 App 的显示精度。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("模拟会话") {
                    Text(status).accessibilityIdentifier("precisionStatus")
                    if pendingRecovery {
                        Label("存在未确认恢复的会话；不要把关闭 App 当作恢复定位。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Button("开始 / 更新目标位置") { start() }
                        .disabled(target == nil || busy || session.routeCoordinates != nil)
                    Button("停止模拟并请求恢复", role: .destructive) { clear() }.disabled(busy)
                    if pendingRecovery && !session.isActive {
                        Button("我已在设备上验证真实定位恢复") {
                            pendingRecovery = false
                            status = "用户已确认恢复；未启动模拟"
                        }.disabled(busy)
                    }
                    if busy { ProgressView("正在与设备通信…") }
                    Text("清除命令发送成功仍需验证。切换 App、锁屏或强制退出可能中断会话；恢复后请检查地图位置及实际移动更新。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("精确定位")
            .onAppear {
                if pendingRecovery { status = "上次会话尚未确认恢复，请先清除或验证" }
            }
        }
    }

    private func formatted(_ p: PrecisionGeodesy.Point) -> String {
        String(format: "%.8f, %.8f", p.latitude, p.longitude)
    }

    private func calculate() {
        guard let anchor, let metres = Double(distance), let degrees = Double(bearing),
              let point = PrecisionGeodesy.offset(from: anchor, metres: metres, bearing: degrees) else {
            target = nil; status = "距离或方位无效，请重新输入"; return
        }
        target = point
        status = "目标已计算，尚未发送"
    }

    private func start() {
        guard let point = target, !busy else { return }
        guard !pendingRecovery || session.isActive else {
            status = "请先处理上次未确认恢复的会话"; return
        }
        let path = PairingFileStore.prepareURL().path
        guard FileManager.default.fileExists(atPath: path) else {
            status = "缺少配对文件，请先完成连接设置"; return
        }
        let ip = DeviceConnectionContext.targetIPAddress
        session.pauseResending()
        pendingRecovery = true // Persist before sending: a crash must not look like a clean exit.
        busy = true
        LocationSimulationCommandQueue.shared.async {
            let code = simulate_location(ip, point.latitude, point.longitude, path)
            DispatchQueue.main.async {
                busy = false
                guard code == 0 else { status = "设置失败（\(code)），恢复状态未知"; return }
                status = "坐标已发送；请在目标 App 验证"
                session.startResending(at: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                    LocationSimulationCommandQueue.shared.async {
                        let retry = simulate_location(ip, point.latitude, point.longitude, path)
                        if retry != 0 {
                            DispatchQueue.main.async {
                                session.pauseResending()
                                status = "连接中断（\(retry)），已停止重发；请请求恢复"
                            }
                        }
                    }
                }
            }
        }
    }

    private func clear() {
        guard !busy else { return }
        session.pauseResending()
        session.clearRoute()
        busy = true
        LocationSimulationCommandQueue.shared.async {
            let code = clear_simulated_location()
            DispatchQueue.main.async {
                busy = false
                session.stop() // Stop this session's keep-alive even if the transport failed.
                pendingRecovery = true
                status = code == 0
                    ? "清除命令已发送，真实定位恢复待验证"
                    : "清除失败（\(code)）；请检查 VPN、连接和镜像后重试，必要时重启设备并验证"
            }
        }
    }
}
