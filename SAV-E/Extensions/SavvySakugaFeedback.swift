import SwiftUI
import UIKit
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
import WebKit
#endif

extension View {
    @ViewBuilder func savvyPressFeedback(prominent: Bool = false, plain: Bool = true) -> some View {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
        buttonStyle(SakugaActionStyle(prominent: prominent))
#else
        if plain { buttonStyle(.plain) } else { self }
#endif
    }
    @ViewBuilder func savvyInputFeedback() -> some View {
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
        overlay { SakugaInputBridge().allowsHitTesting(false).accessibilityHidden(true) }
#else
        self
#endif
    }
}

#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
// Adapter to the native port in SakugaNativeDrawing.swift (upstream MIT).
// Only successful native Button activation fires impact. Drag-out/cancel just
// releases the spring; there is no replacement gesture or inferred save success.
private struct SakugaActionStyle: PrimitiveButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        SakugaAction(configuration: configuration, prominent: prominent)
    }
}

private struct SakugaAction: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let prominent: Bool
    @StateObject private var motion = SakugaButtonMotion()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scene
    @Environment(\.isEnabled) private var enabled
    // Disabling after an accepted async action prevents another click, but must
    // not cancel that click’s decorative impact. Lifecycle/RM still cancel it.
    private var active: Bool { !reduceMotion && scene == .active }
    var body: some View {
        Button {
            if active && enabled { motion.activate(primary: prominent) }
            configuration.trigger()
        } label: { configuration.label }
        .buttonStyle(SakugaTrackingStyle(motion: motion, primary: prominent, active: active))
        .onChange(of: active) { _, value in if !value { motion.stop() } }
        .onDisappear { motion.stop() }
    }
}

private struct SakugaTrackingStyle: ButtonStyle {
    @ObservedObject var motion: SakugaButtonMotion
    let primary: Bool
    let active: Bool
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.colorScheme, motion.flash && active ? (scheme == .light ? .dark : .light) : scheme)
            .scaleEffect(x: active ? motion.transform.x : 1, y: active ? motion.transform.y : 1)
            .rotationEffect(.degrees(active ? motion.transform.angle : 0))
            .background { SakugaButtonBackLayer(motion: motion).padding(-160).allowsHitTesting(false).accessibilityHidden(true) }
            .onChange(of: configuration.isPressed) { _, down in
                if active { motion.press(down, primary: primary) }
            }
    }
}

@MainActor private final class SakugaButtonMotion: ObservableObject {
    struct Transform { var x = 1.0; var y = 1.0; var angle = 0.0 }
    @Published var transform = Transform()
    @Published var flash = false
    weak var anchor: SakugaCanvasView?
    let owner = UUID()
    private var squash = SakugaSpring(1,520,15)
    private var pop = SakugaSpring(1,300,12)
    private var tilt = SakugaSpring(0,260,10)
    private var wide = 0.24
    private var elapsed = 0.0
    private var impactAt: Double?
    private var recoiled = false
    private var controlRect: CGRect? {
        guard let anchor, let window=anchor.window else{return nil}
        return anchor.convert(anchor.bounds.insetBy(dx:160,dy:160),to:window)
    }
    func press(_ down: Bool, primary: Bool) {
        wide = primary ? 0.24:0.3
        squash.target = down ? (primary ? 0.5:0.72):1
        if down,primary,let anchor,let rect=controlRect,let window=anchor.window {
            let overlay=SakugaCanvasView.overlay(in:window);overlay.particles.press(owner,rect:rect);overlay.start()
        }
        anchor?.start()
    }
    func activate(primary: Bool) {
        guard let anchor,let window=anchor.window,let rect=controlRect else{return}
        wide = primary ? 0.24:0.3; squash.target=1
        if primary {
            squash.x=min(squash.x,0.6);pop.x=1.24;tilt.x = -5
            impactAt=elapsed;recoiled=false;flash=true
            anchor.particles.clear(owner:owner)
            anchor.particles.burst(owner,x:anchor.bounds.midX,y:anchor.bounds.midY)
        } else {squash.x=min(squash.x,0.8);squash.v+=4}
        let overlay=SakugaCanvasView.overlay(in:window)
        overlay.particles.impact(owner,rect:rect,primary:primary);overlay.start();anchor.start()
    }
    func step(_ dt: Double)->Bool {
        elapsed+=dt
        if let impactAt {
            let age=elapsed-impactAt
            if age>=0.19,flash {flash=false}
            if age>=0.2,!recoiled {squash.x=1.22;recoiled=true}
            if age>=0.21 {self.impactAt=nil}
        }
        let y=squash.step(dt),p=pop.step(dt),angle=tilt.step(dt)
        transform=Transform(x:(1+(1-y)*wide)*p,y:y*p,angle:angle)
        return impactAt != nil || !squash.settled || !pop.settled || !tilt.settled
    }
    func stop() {
        if let window=anchor?.window {SakugaCanvasView.existingOverlay(in:window)?.particles.clear(owner:owner)}
        anchor?.stop();squash=SakugaSpring(1,520,15);pop=SakugaSpring(1,300,12);tilt=SakugaSpring(0,260,10)
        impactAt=nil;flash=false;transform=Transform()
    }
}

private struct SakugaButtonBackLayer: UIViewRepresentable {
    let motion: SakugaButtonMotion
    func makeUIView(context: Context)->SakugaCanvasView {
        let view=SakugaCanvasView();motion.anchor=view
        view.advance={ [weak motion] dt in motion?.step(dt) ?? false }
        return view
    }
    func updateUIView(_ view: SakugaCanvasView,context: Context) { motion.anchor=view }
    static func dismantleUIView(_ view: SakugaCanvasView,coordinator: ()) { view.stop();view.advance=nil }
}

/// Transparent drawing only. One window overlay replaces upstream's global
/// effects canvas; button bursts use its separate back layer. No WKWebView.
@MainActor class SakugaCanvasView: UIView {
    let particles=SakugaParticles()
    var advance: ((Double)->Bool)?
    var customPaint: ((CGContext,SakugaPaint)->Void)?
    private var link: CADisplayLink?
    private var previous = 0.0
    var isWindowOverlay = false
    override init(frame:CGRect) {
        super.init(frame:frame);isOpaque=false;backgroundColor = .clear
        isUserInteractionEnabled=false;isAccessibilityElement=false;contentMode = .redraw
        NotificationCenter.default.addObserver(self,selector:#selector(suspend),name:UIApplication.willResignActiveNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(reduceChanged),name:UIAccessibility.reduceMotionStatusDidChangeNotification,object:nil)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    static func existingOverlay(in window:UIWindow)->SakugaCanvasView? {
        window.subviews.compactMap {$0 as? SakugaCanvasView}.first {$0.isWindowOverlay}
    }
    static func overlay(in window:UIWindow)->SakugaCanvasView {
        if let view=existingOverlay(in:window) {window.bringSubviewToFront(view);return view}
        let view=SakugaCanvasView(frame:window.bounds);view.isWindowOverlay=true;view.autoresizingMask=[.flexibleWidth,.flexibleHeight]
        window.addSubview(view);return view
    }
    func start() {
        guard link==nil,window != nil,!UIAccessibility.isReduceMotionEnabled,
              window?.windowScene?.activationState == .foregroundActive else{return}
        previous=0
        let target=SakugaDisplayTarget();target.view=self
        let link=CADisplayLink(target:target,selector:#selector(SakugaDisplayTarget.frame(_:)))
        link.preferredFrameRateRange=CAFrameRateRange(minimum:30,maximum:60,preferred:60)
        self.link=link;link.add(to:.main,forMode:.common)
    }
    func stop() {link?.invalidate();link=nil;previous=0;particles.clear();setNeedsDisplay()}
    @objc private func suspend() {stop()}
    @objc private func reduceChanged() {if UIAccessibility.isReduceMotionEnabled {stop()}}
    override func didMoveToWindow() {super.didMoveToWindow();if window==nil {stop()}}
    fileprivate func frame(_ tick:CADisplayLink) {
        let dt=previous==0 ? 1.0/60:min(max(tick.timestamp-previous,0),0.034);previous=tick.timestamp
        let continuing=advance?(dt) ?? false
        particles.step(dt);setNeedsDisplay()
        if !continuing && particles.isEmpty {link?.invalidate();link=nil;previous=0}
    }
    override func draw(_ rect:CGRect) {
        guard let g=UIGraphicsGetCurrentContext() else{return}
        g.setLineCap(.round);g.setLineJoin(.round)
        let palette=SakugaPaint(traits:traitCollection)
        customPaint?(g,palette);particles.draw(g,paint:palette)
    }
}

@MainActor private final class SakugaDisplayTarget:NSObject {
    weak var view:SakugaCanvasView?
    @objc func frame(_ link:CADisplayLink) {if let view {view.frame(link)}else{link.invalidate()}}
}

/// Original MIT Sakuga progress, bundled offline; native buttons/input keep their port.
struct SavvyOriginalOpening: UIViewRepresentable {
    let startedAt: Double?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.appLanguageSettings) private var language
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        if let file = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "SakugaOpening") {
            view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.state = ["dark": scheme == .dark, "active": scene == .active,
            "reduced": reduced, "elapsed": max(0, CACurrentMediaTime() - (startedAt ?? CACurrentMediaTime())),
            "label": language.localized(english: "Opening animation", traditionalChinese: "開場動畫")]
        context.coordinator.update(view)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var state: [String: Any] = [:]
        private var ready = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true; update(webView)
        }
        func update(_ view: WKWebView) {
            guard ready, let data = try? JSONSerialization.data(withJSONObject: state),
                  let json = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("window.savvyOpening(\(json))", completionHandler: nil)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .other && action.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}

// A presentation clock, not a network/authentication completion claim.
struct SavvyOpeningProgress {
    static let duration = 1.5
    private(set) var value = 0.0
    mutating func update(elapsed: Double) {
        guard elapsed.isFinite else { return }
        value = max(value, min(1, max(0, elapsed / Self.duration)))
    }
    var percent: Int { min(100, Int(value * 100)) }
}

private struct SavvyOpeningStartKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}
extension EnvironmentValues {
    var savvyOpeningStart: Double? {
        get { self[SavvyOpeningStartKey.self] }
        set { self[SavvyOpeningStartKey.self] = newValue }
    }
}

struct SavvyLoadingCloud: UIViewRepresentable {
    @Environment(\.appLanguageSettings) private var language
    var openingStartedAt: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scene
    func makeUIView(context:Context)->SakugaProgressCanvas {SakugaProgressCanvas()}
    func updateUIView(_ view:SakugaProgressCanvas,context:Context) {
        view.accessibilityLabel = language.localized(english: "Opening animation", traditionalChinese: "開場動畫")
        view.configure(startedAt: openingStartedAt, reducedMotion: reduceMotion)
        view.setActive(!reduceMotion && scene == .active)
    }
    static func dismantleUIView(_ view:SakugaProgressCanvas,coordinator:()) {view.stop()}
}

/// Upstream 12-lobe storm geometry, shadow, rumble art, ground and flying wisps.
/// The full-size bar shows timed opening-animation progress, never auth progress.
/// Compact loaders retain the cloud-only treatment.
@MainActor final class SakugaProgressCanvas:SakugaCanvasView {
    private static let lobes:[(Double,Double,Double)]=[(0,-0.95,1),(0.78,-0.55,0.74),(-0.72,-0.78,0.72),(0.36,-1.7,0.7),(-0.4,-1.62,0.62),(1.1,-1.32,0.52),(-1.18,-0.28,0.52),(0.62,0.3,0.5),(-0.86,0.5,0.52),(-1.5,0.82,0.38),(-2.05,1,0.24),(0.16,0.72,0.4)]
    private let phases=(0..<12).map {_ in SakugaMath.random(0,6.28)}
    private let speeds=(0..<12).map {_ in SakugaMath.random(1.4,2.6)}
    private struct Pebble {
        let position: Double
        let size = SakugaMath.random(3.4, 5.6)
        let phase = SakugaMath.random(0, 6.28)
        let rotation = SakugaMath.random(-0.5, 0.5)
        var lift = SakugaSpring(0, 70, 7)
        let points = [(-1.0, 0.4), (-0.5, -0.8), (0.5, -1), (1, 0.1), (0.3, 0.9)]
            .map { ($0.0 * SakugaMath.random(0.8, 1.2), $0.1 * SakugaMath.random(0.8, 1.2)) }
    }
    private var pebbles = [0.14, 0.31, 0.5, 0.69, 0.87].map { Pebble(position: $0) }
    private let owner=UUID()
    private weak var effectWindow: UIWindow?
    private var active=false,time=0.0,emission=0.0,lastRumble = -10.0
    private var opening = SavvyOpeningProgress()
    private var startedAt = CACurrentMediaTime()
    private var previousProgress = 0.0
    func configure(startedAt: Double?, reducedMotion: Bool) {
        if let startedAt { self.startedAt = startedAt }
        if reducedMotion { opening.update(elapsed: SavvyOpeningProgress.duration) }
        else { opening.update(elapsed: CACurrentMediaTime() - self.startedAt) }
        accessibilityValue = "\(opening.percent)%"
        setNeedsDisplay()
    }
    private var cloudSize=SakugaSpring(22,90,13),lag=SakugaSpring(0,120,16)
    override init(frame:CGRect) {
        super.init(frame:frame)
        advance={ [weak self] dt in self?.step(dt) ?? false }
        customPaint={ [weak self] g,p in self?.paint(g,p) }
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func setActive(_ value:Bool) {
        active=value
        if value { start() } else { stop() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        isAccessibilityElement = bounds.height >= 100
    }
    override func didMoveToWindow() {super.didMoveToWindow();if active {start()}}
    override func stop() {
        if let effectWindow { SakugaCanvasView.existingOverlay(in:effectWindow)?.particles.clear(owner:owner) }
        effectWindow=nil
        super.stop()
    }
    private var phase:Double { bounds.height < 100 ? 0.5 : opening.value }
    private func step(_ dt:Double)->Bool {
        guard active else{return false};time+=dt
        opening.update(elapsed: CACurrentMediaTime() - startedAt)
        let velocity = min(1, max(0, (phase - previousProgress) / max(dt, 0.001)))
        previousProgress = phase
        accessibilityValue = "\(opening.percent)%"
        cloudSize.target=10+25*sqrt(phase);_ = cloudSize.step(dt)
        lag.target=velocity;_ = lag.step(dt)
        for index in pebbles.indices {
            pebbles[index].lift.target = 4+272*phase > 280*pebbles[index].position-16 ? 1:0
            _ = pebbles[index].lift.step(dt)
        }
        if bounds.height>=100,opening.value < 1,let window {
            effectWindow=window
            let effects=SakugaCanvasView.overlay(in:window)
            let origin=convert(CGPoint.zero,to:window)
            emission+=dt*(4+abs(velocity)*60)
            if emission>=1 {
                emission-=1
                let scale=min(bounds.width/420,bounds.height/210),lead=4+272*phase,top=75.0,s=cloudSize.x
                let ox=origin.x+bounds.midX-140*scale,oy=origin.y+bounds.midY-90*scale
                if Bool.random() {
                    effects.particles.puff(owner,x:ox+(lead-s*SakugaMath.random(0.9,1.6))*scale,y:oy+(top-s*SakugaMath.random(0.1,0.9))*scale,size:(SakugaMath.random(3,5.5)+phase*3)*scale,n:2,vx: -SakugaMath.random(40,90)*scale,vy:SakugaMath.random(-12,4)*scale,life:SakugaMath.random(0.4,0.7))
                } else {effects.particles.lines(owner,x:ox+(lead-s*1.4)*scale,y:oy+(top-s*SakugaMath.random(0.2,1.3))*scale,length:(30+abs(velocity)*160)*scale)}
            }
            if time-lastRumble>5 {
                lastRumble=time;let scale=min(bounds.width/420,bounds.height/210)
                effects.particles.lettering(owner,name:"gogo",x:origin.x+bounds.midX-34*scale,y:origin.y+bounds.midY-81*scale,size:150*scale,life:2.9,rotation:-0.1)
            }
            if !effects.particles.isEmpty { effects.start() }
        }
        return bounds.height < 100 || opening.value < 1
    }
    private func paint(_ g:CGContext,_ p:SakugaPaint) {
        let compact=bounds.height<100
        let scale=compact ? min(bounds.width/100,bounds.height/85):min(bounds.width/420,bounds.height/210)
        g.saveGState();g.translateBy(x:bounds.midX-(compact ? 50:140)*scale,y:bounds.midY-(compact ? 42.5:90)*scale);g.scaleBy(x:scale,y:scale)
        let s=compact ? 22:cloudSize.x,lead=compact ? 58:4+272*phase,cy=compact ? 53.0:94.0
        if !compact {
            let bar=CGRect(x:0,y:75,width:280,height:38),path=UIBezierPath(roundedRect:bar,cornerRadius:19).cgPath
            g.addPath(path);g.setFillColor(p.fill);g.setStrokeColor(p.ink);g.setLineWidth(4);g.drawPath(using:.fillStroke)
            g.saveGState();g.addPath(path);g.clip();g.setFillColor(p.accent)
            g.fill(CGRect(x:4,y:79,width:272*phase,height:30))
            g.setFillColor(p.fill)
            for (offset,width) in [(22.0,9.0),(37.0,6.0)] {
                let q=CGMutablePath(),x=lead-48+offset
                q.move(to:CGPoint(x:x+6,y:84));q.addLine(to:CGPoint(x:x+width+6,y:84));q.addLine(to:CGPoint(x:x+width,y:95));q.addLine(to:CGPoint(x:x,y:95));q.closeSubpath();g.addPath(q);g.fillPath()
            };g.restoreGState()
            let reach = SakugaMath.clamp(phase*1.25), groundEnd = 10+260*reach
            g.setStrokeColor(p.line);g.setLineWidth(1.4)
            g.move(to:CGPoint(x:10,y:143));g.addLine(to:CGPoint(x:groundEnd,y:143))
            for x in stride(from:26.0,to:groundEnd-6,by:37) {
                g.move(to:CGPoint(x:x,y:143));g.addLine(to:CGPoint(x:x+3,y:139))
                g.move(to:CGPoint(x:x+5,y:143));g.addLine(to:CGPoint(x:x+6.5,y:140.5))
            }
            g.strokePath()
            for pebble in pebbles {
                let up=pebble.lift.x,stone=pebble.size,px=280*pebble.position
                guard reach >= pebble.position-0.04 || up >= 0.01 else { continue }
                let y=143-stone*0.7-up*(7+stone*1.5)+sin(time*3+pebble.phase)*2*up
                g.saveGState();g.translateBy(x:px,y:y)
                g.rotate(by:pebble.rotation+up*sin(time*2+pebble.phase)*0.5)
                let shape=CGMutablePath()
                for (index,point) in pebble.points.enumerated() {
                    let v=CGPoint(x:point.0*stone,y:point.1*stone)
                    if index==0 {shape.move(to:v)}else{shape.addLine(to:v)}
                }
                shape.closeSubpath();p.shape(g,shape,width:1.1,offset:stone*0.5);g.restoreGState()
                if up>0.15 && up<0.9 && pebble.lift.v>0.6 {
                    g.setStrokeColor(p.accent);g.setLineWidth(2.4)
                    for angle in [-1.9,-1.57,-1.24] {
                        g.move(to:CGPoint(x:px+cos(angle)*(stone+5),y:y+sin(angle)*(stone+5)))
                        g.addLine(to:CGPoint(x:px+cos(angle)*(stone+11),y:y+sin(angle)*(stone+11)))
                    }
                    g.strokePath()
                }
            }
        }
        if !compact {
            // Numeral uses the same value as fill and cloud; no spring overshoot.
            let label = "\(opening.percent)%" as NSString
            let font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(cgColor: p.ink)]
            let width = label.size(withAttributes: attrs).width
            let tag = CGRect(x: 140-width/2-12, y: 157, width: width+24, height: 28)
            let path = UIBezierPath(roundedRect: tag, cornerRadius: 8).cgPath
            g.addPath(path);g.setFillColor(p.fill);g.setStrokeColor(p.ink);g.setLineWidth(1.5);g.drawPath(using:.fillStroke)
            label.draw(at: CGPoint(x:140-width/2,y:161),withAttributes:attrs)
        }
        let circles=Self.lobes.enumerated().map { i,l in
            let boil=1+0.16*sin(time*speeds[i]+phases[i]),roll=0.82+0.22*sin(time*2.6-Double(i)*0.9)
            return (lead+3+(l.0+cos(time*speeds[i]*0.7+phases[i])*0.1-lag.x*1.6*max(0,-l.1)*0.5)*s,
                    cy-3+(l.1+sin(time*speeds[i]*0.7+phases[i])*0.1)*s,l.2*s*boil*roll)
        }
        p.blob(g,circles,width:1.6,lightX:1,arcs:true,depth:1.7);g.restoreGState()
    }
}

private struct SakugaInputBridge:UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scene
    func makeUIView(context:Context)->SakugaInputObserver {SakugaInputObserver()}
    func updateUIView(_ view:SakugaInputObserver,context:Context) {view.enabled = !reduceMotion && scene == .active}
    static func dismantleUIView(_ view:SakugaInputObserver,coordinator:()) {view.stop()}
}

/// Native text, selection, marked ranges and delegates remain owned by UIKit.
/// Only caret geometry crosses into the effect renderer, never entered text.
private final class SakugaInputObserver:UIView {
    var enabled=true {didSet{if !enabled{clear()}}}
    private let owner=UUID()
    private weak var field:UIView?
    private var inputSpring=SakugaSpring(1,700,16)
    private var springTime:CFTimeInterval?
    override init(frame:CGRect) {super.init(frame:frame);isUserInteractionEnabled=false;isAccessibilityElement=false}
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func didMoveToWindow() {
        super.didMoveToWindow();stop();guard window != nil else{return}
        for name in [UITextField.textDidBeginEditingNotification,UITextField.textDidChangeNotification,UITextField.textDidEndEditingNotification,
                     UITextView.textDidBeginEditingNotification,UITextView.textDidChangeNotification,UITextView.textDidEndEditingNotification] {
            NotificationCenter.default.addObserver(self,selector:#selector(receive(_:)),name:name,object:nil)
        }
    }
    func stop(){NotificationCenter.default.removeObserver(self);clear()}
    private func clear() {
        field?.layer.removeAnimation(forKey:"savvy.sakuga.input")
        if let window {SakugaCanvasView.existingOverlay(in:window)?.particles.clear(owner:owner)}
        field=nil;inputSpring=SakugaSpring(1,700,16);springTime=nil
    }
    @objc private func receive(_ note:Notification) {
        guard enabled,!UIAccessibility.isReduceMotionEnabled,let window,
              let input=note.object as? (UIView & UITextInput),input.window === window else{return}
        guard (input as? UITextField)?.isSecureTextEntry != true,
              (input as? UITextView)?.isSecureTextEntry != true else{return}
        let local=input.convert(input.bounds,to:self)
        guard bounds.insetBy(dx:-2,dy:-2).contains(CGPoint(x:local.midX,y:local.midY)) else{return}
        if note.name==UITextField.textDidEndEditingNotification || note.name==UITextView.textDidEndEditingNotification {clear();return}
        guard input.isFirstResponder else{return}
        if field !== input {clear()}
        field=input
        let effects=SakugaCanvasView.overlay(in:window)
        if note.name==UITextField.textDidBeginEditingNotification || note.name==UITextView.textDidBeginEditingNotification {
            let box=input.convert(input.bounds,to:window)
            effects.particles.ticks(owner,x:box.maxX-6,y:box.minY-4)
            kick(input,from:1.04)
        } else {
            // No particles while the Chinese IME is composing. Paste remains
            // one native edit, not a loop over the pasted string's characters.
            guard input.markedTextRange==nil,let selected=input.selectedTextRange else{return}
            let caret=input.caretRect(for:selected.end)
            guard input.bounds.insetBy(dx:-2,dy:-2).contains(CGPoint(x:caret.midX,y:caret.midY)) else{return}
            let effectY = input is UITextView ? caret.maxY+4 : input.bounds.midY+10
            let point=input.convert(CGPoint(x:caret.midX,y:effectY),to:window)
            effects.particles.puff(owner,x:point.x,y:point.y,size:SakugaMath.random(4,6),n:2,vx:SakugaMath.random(-10,10),vy:-22,life:0.4)
            if Double.random(in:0...1)<0.35 {effects.particles.shards(owner,x:point.x,y:point.y-4,n:2,speed:110,size:3,life:0.5,arc:.pi,gravity:420)}
            kick(input,from:0.985)
        }
        effects.start()
    }
    private func kick(_ input:UIView,from value:Double) {
        let now=CACurrentMediaTime()
        if let springTime {
            // Reconstruct the running spring at this edit, retaining velocity
            // just as upstream changes s.x without replacing the spring.
            var remaining=min(max(now-springTime,0),2)
            while remaining>0 {
                let dt=min(remaining,1.0/60)
                _ = inputSpring.step(dt);remaining-=dt
            }
        }
        inputSpring.x=value;inputSpring.target=1;springTime=now
        var sampled=inputSpring
        var samples=[value]
        for _ in 0..<120 {samples.append(sampled.step(1.0/60))}
        let animation=CAKeyframeAnimation(keyPath:"transform.scale")
        animation.values=samples;animation.duration=2;animation.calculationMode = .linear
        input.layer.add(animation,forKey:"savvy.sakuga.input")
    }
}
#endif
