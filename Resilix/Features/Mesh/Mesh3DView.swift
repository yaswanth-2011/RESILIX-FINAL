import SwiftUI
import SceneKit

struct Mesh3DView: UIViewRepresentable {
    var peers: [MeshNode]
    var isDemo: Bool = false
    var compact: Bool = false

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)
        view.allowsCameraControl = !compact
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        let rotate = CABasicAnimation(keyPath: "rotation")
        rotate.fromValue = NSValue(scnVector4: SCNVector4(0, 1, 0, 0))
        rotate.toValue = NSValue(scnVector4: SCNVector4(0, 1, 0, Float.pi * 2))
        rotate.duration = compact ? 22 : 28
        rotate.repeatCount = .infinity
        view.scene?.rootNode.addAnimation(rotate, forKey: "slowRotate")
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = makeScene()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = compact ? 48 : 55
        cameraNode.position = SCNVector3(0, compact ? 0.8 : 1.2, compact ? 4.5 : 6)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 900
        light.position = SCNVector3(0, 5, 5)
        scene.rootNode.addChildNode(light)
        let center = sphere(radius: compact ? 0.24 : 0.32, color: UIColor(red: 0.42, green: 0.55, blue: 0.65, alpha: 1), glow: true)
        center.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(center)
        let count = max(peers.count, 3)
        for (i, peer) in peers.prefix(5).enumerated() {
            let angle = Float(i) * (Float.pi * 2 / Float(count)) - Float.pi/2
            let r: Float = compact ? 1.4 : 1.9
            let pos = SCNVector3(cos(angle)*r, sin(angle)*r*0.45, 0)
            let node = sphere(radius: compact ? 0.14 : 0.18, color: peer.isRelay ? UIColor(red: 0.52, green: 0.62, blue: 0.72, alpha: 1) : UIColor(white: 0.92, alpha: 1), glow: peer.isRelay)
            node.position = pos
            scene.rootNode.addChildNode(node)
            let line = cylinder(from: SCNVector3(0,0,0), to: pos, color: UIColor(red: 0.42, green: 0.55, blue: 0.65, alpha: 0.45))
            scene.rootNode.addChildNode(line)
            let dot = SCNSphere(radius: 0.04)
            dot.firstMaterial?.diffuse.contents = UIColor(red: 0.52, green: 0.62, blue: 0.72, alpha: 1)
            dot.firstMaterial?.emission.contents = UIColor(red: 0.52, green: 0.62, blue: 0.72, alpha: 1)
            let dotNode = SCNNode(geometry: dot)
            dotNode.position = pos
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = SCNVector3(0,0,0)
            move.toValue = pos
            move.duration = 2.2 + Double(i)*0.3
            move.autoreverses = true
            move.repeatCount = .infinity
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dotNode.addAnimation(move, forKey: "travel")
            scene.rootNode.addChildNode(dotNode)
        }
        return scene
    }

    private func sphere(radius: CGFloat, color: UIColor, glow: Bool) -> SCNNode {
        let geo = SCNSphere(radius: radius)
        geo.firstMaterial?.diffuse.contents = color
        geo.firstMaterial?.lightingModel = .blinn
        if glow {
            geo.firstMaterial?.emission.contents = color.withAlphaComponent(0.35)
            geo.firstMaterial?.emission.intensity = 0.6
        }
        geo.segmentCount = 28
        return SCNNode(geometry: geo)
    }

    private func cylinder(from: SCNVector3, to: SCNVector3, color: UIColor) -> SCNNode {
        let dx = to.x - from.x; let dy = to.y - from.y; let dz = to.z - from.z
        let dist = sqrt(dx*dx + dy*dy + dz*dz)
        let cyl = SCNCylinder(radius: 0.012, height: CGFloat(dist))
        cyl.firstMaterial?.diffuse.contents = color
        cyl.firstMaterial?.emission.contents = color.withAlphaComponent(0.25)
        let node = SCNNode(geometry: cyl)
        node.position = SCNVector3((from.x+to.x)/2, (from.y+to.y)/2, (from.z+to.z)/2)
        node.look(at: to, up: SCNVector3(0,0,1), localFront: SCNVector3(0,1,0))
        return node
    }
}
