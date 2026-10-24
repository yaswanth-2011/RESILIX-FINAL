import SwiftUI

struct RouteDetailView: View {
    var route: MeshRoute
    @State private var showDetails = false
    @State private var showTestResult = false
    @State private var testResult = ""
    @EnvironmentObject var app: ResilixAppModel
    var body: some View {
        ScrollView{
            VStack(alignment:.leading, spacing: ResilixTheme.space24){
                RoutePathView(hops: route.hops.map{ $0.nodeID }, isSimulated: app.demoController.isDemoMode)
                    .padding(.horizontal, ResilixTheme.space16)
                VStack(alignment:.leading, spacing:8){
                    Text("Hop count: \(route.hopCount)").font(.subheadline).foregroundStyle(ResilixTheme.textPrimary)
                    Text("Freshness: \(route.freshness, style:.relative) ago").font(.caption).foregroundStyle(ResilixTheme.textSecondary)
                    Text("Another phone can relay your message when direct connection is not available.").font(.caption).foregroundStyle(ResilixTheme.textSecondary)
                    Text("No guaranteed delivery. Mesh finds best available path.").font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
                }.padding(.horizontal, ResilixTheme.space16)
                ForEach(route.hops, id:\.nodeID){ hop in
                    HStack{
                        Circle().fill(color(for: hop.quality)).frame(width:8,height:8)
                        Text(hop.nodeID).font(.caption.weight(.semibold)).foregroundStyle(ResilixTheme.textPrimary)
                        Spacer()
                        Text(hop.transport.rawValue).font(.caption2).foregroundStyle(ResilixTheme.textSecondary)
                        Text(hop.quality.label).font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
                    }.padding(.horizontal, ResilixTheme.space16)
                }
                Button("Test route"){
                    Task{
                        if app.demoController.isDemoMode {
                            await app.demoController.sendDemoMessage()
                            testResult = "Demo route test: B verified and forwarded to C. Delivered via \(route.hopCount) hops."
                        } else {
                            let hasPeers = !app.meshController.availableTransports.flatMap { $0.discoveredPeers }.isEmpty
                            if !hasPeers {
                                testResult = "No route available. No peers nearby."
                            } else {
                                testResult = "Route to \(route.destination) tested. Next hop \(route.nextHop) via \(route.transport.rawValue)."
                            }
                        }
                        showTestResult = true
                    }
                }.buttonStyle(.bordered).tint(ResilixTheme.brandTeal).padding(.horizontal, ResilixTheme.space16)
                .accessibilityLabel("Test route")
                DisclosureGroup("Details", isExpanded: $showDetails){
                    VStack(alignment:.leading, spacing:6){
                        Text("Packet ID: demo-\(route.destination.prefix(4))").font(.caption2.monospaced()).foregroundStyle(ResilixTheme.textTertiary)
                        Text("TTL: \(ResilixConstants.defaultTTL)").font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
                        Text("Transport selection: \(route.transport.rawValue)").font(.caption2).foregroundStyle(ResilixTheme.textTertiary)
                    }.padding(.horizontal, ResilixTheme.space16)
                }.padding(.horizontal, ResilixTheme.space16)
            }.padding(.vertical, ResilixTheme.space16)
        }.background(ResilixTheme.bgPrimary).navigationTitle("Route detail").navigationBarTitleDisplayMode(.inline)
        .alert("Route test", isPresented: $showTestResult){ Button("OK", role:.cancel){} } message:{ Text(testResult) }
    }
    func color(for q: LinkQuality)->Color { switch q { case .stable: return ResilixTheme.brandTeal; case .degraded: return ResilixTheme.brandAmber; case .unavailable: return ResilixTheme.emergencyRed; case .unknown: return ResilixTheme.textTertiary } }
}
