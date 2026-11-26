/*
MIT License

Copyright (c) 2026 Justin Finkelman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
#if DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW
import UIKit
import SwiftUI

// Native port of Sakuga core.js, button.js, input.js and progress.js at
// c3dabb173928a3ad2372183103caf2e6f50953d0. Equations and geometry are upstream;
// palette, native control bindings and indeterminate loading are Savvy adapters.
struct SakugaSpring {
    var x: Double
    var v = 0.0
    var target: Double
    let stiffness: Double
    let damping: Double
    init(_ x: Double, _ stiffness: Double, _ damping: Double) {
        self.x = x; target = x; self.stiffness = stiffness; self.damping = damping
    }
    mutating func step(_ dt: Double) -> Double {
        guard dt > 0 else { return x }
        let n = Int(ceil(dt / 0.008)), h = dt / Double(n)
        for _ in 0..<n { v += (-stiffness * (x - target) - damping * v) * h; x += v * h }
        return x
    }
    var settled: Bool { abs(x - target) < 0.001 && abs(v) < 0.01 }
}

enum SakugaMath {
    static func clamp(_ n: Double) -> Double { min(1, max(0, n)) }
    static func out(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func inside(_ t: Double) -> Double { t * t * t }
    static func back(_ t: Double) -> Double { 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2) }
    static func random(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b) }
}

struct SakugaPaint {
    let fill: CGColor, shade: CGColor, line: CGColor, accent: CGColor, ink: CGColor
    init(traits: UITraitCollection) {
        func color(_ c: Color) -> CGColor { UIColor(c).resolvedColor(with: traits).cgColor }
        fill = color(SaveBrandUI.surface); shade = color(SaveBrandUI.brand)
        line = color(SaveBrandUI.ink); accent = color(SaveBrandUI.accent); ink = color(SaveBrandUI.ink)
    }
    func blob(_ g: CGContext, _ circles: [(Double, Double, Double)], width: Double = 1.5,
              lightX: Double = -1, arcs: Bool = false, depth: Double = 1) {
        let path = CGMutablePath()
        for (x, y, r) in circles where r > 0.3 { path.addEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2)) }
        g.saveGState(); g.addPath(path); g.setStrokeColor(line); g.setLineWidth(width*2); g.strokePath(); g.restoreGState()
        g.saveGState(); g.addPath(path); g.clip(); g.setFillColor(shade); g.fill(CGRect(x: -10000, y: -10000, width: 20000, height: 20000))
        let r = circles.first?.2 ?? 8
        g.saveGState(); g.translateBy(x: lightX*r*0.2*depth, y: -r*0.26*depth)
        g.addPath(path); g.setFillColor(fill); g.fillPath(); g.restoreGState()
        if arcs {
            g.setStrokeColor(line); g.setLineWidth(width*0.75)
            for (x, y, r) in circles where r > 3 {
                g.move(to: CGPoint(x: x+cos(-2.7)*r, y: y+sin(-2.7)*r))
                g.addArc(center: CGPoint(x:x,y:y), radius:r, startAngle:-2.7, endAngle:-0.5, clockwise:false)
            }
            g.strokePath()
        }
        g.restoreGState()
    }
    func shape(_ g: CGContext, _ path: CGPath, width: Double = 1.5, offset: Double = 3) {
        g.saveGState(); g.addPath(path); g.setStrokeColor(line); g.setLineWidth(width*2); g.strokePath(); g.restoreGState()
        g.saveGState(); g.addPath(path); g.clip(); g.setFillColor(shade); g.fill(CGRect(x:-10000,y:-10000,width:20000,height:20000))
        g.translateBy(x:-offset*0.7,y:-offset); g.addPath(path); g.setFillColor(fill); g.fillPath(); g.restoreGState()
    }
}

/// One finite particle queue. Random choices are made at spawn, never at paint.
/// Bounded to 160 live effects; a new click cancels that control's old sequence.
@MainActor final class SakugaParticles {
    struct Effect {
        let owner: UUID, start: Double, life: Double
        let paint: (CGContext, SakugaPaint, Double, Double) -> Void
    }
    private var items: [Effect] = []
    private(set) var time = 0.0
    var isEmpty: Bool { items.isEmpty }
    func clear(owner: UUID? = nil) { if let owner { items.removeAll { $0.owner == owner } } else { items.removeAll() } }
    func step(_ dt: Double) { time += min(max(dt,0),0.034); items.removeAll { time >= $0.start+$0.life } }
    func draw(_ g: CGContext, paint: SakugaPaint) {
        for e in items where time >= e.start {
            let t=time-e.start
            g.saveGState(); e.paint(g,paint,t/e.life,t); g.restoreGState()
        }
    }
    private func add(_ owner: UUID, life: Double, delay: Double = 0,
                     _ paint: @escaping (CGContext,SakugaPaint,Double,Double)->Void) {
        if items.count >= 160 { items.removeFirst() }
        items.append(Effect(owner:owner,start:time+delay,life:life,paint:paint))
    }
    func ticks(_ owner: UUID, x: Double, y: Double, n: Int = 3, radius: Double = 5,
               length: Double = 17, direction: Double = -1.05, life: Double = 0.5, fan: Double = 0.36) {
        add(owner,life:life) { g,p,k,_ in
            let a=SakugaMath.out(SakugaMath.clamp(k/0.5)), b=SakugaMath.inside(SakugaMath.clamp((k-0.4)/0.6))
            g.setFillColor(p.accent)
            for i in 0..<n {
                let angle=direction+(Double(i)-Double(n-1)/2)*fan, r0=radius+length*b*1.25, r1=radius+length*a*1.25
                guard r1-r0 >= 0.6 else { continue }
                let hw=0.07+2.2/(r1+8)
                g.move(to:CGPoint(x:x+cos(angle)*r0,y:y+sin(angle)*r0))
                g.addLine(to:CGPoint(x:x+cos(angle-hw)*r1,y:y+sin(angle-hw)*r1))
                g.addLine(to:CGPoint(x:x+cos(angle+hw)*r1,y:y+sin(angle+hw)*r1)); g.closePath()
            }
            g.fillPath()
        }
    }
    func puff(_ owner: UUID, x: Double, y: Double, size: Double = 13, n: Int = 5,
              vx: Double = 0, vy: Double = -18, life: Double = 0.8, delay: Double = 0) {
        var lobes=(0..<n).map { i in (Double(i)/Double(n)*2*Double.pi+SakugaMath.random(0,0.6), SakugaMath.random(0.25,0.9)*size, SakugaMath.random(0.55,1)*size, SakugaMath.random(0,2 * .pi), SakugaMath.random(0.6,1.3)) }
        lobes.insert((0,0,size,0,1),at:0)
        let frozen=lobes
        add(owner,life:life,delay:delay) { g,p,k,t in
            let grow=SakugaMath.back(SakugaMath.clamp(t/0.22)), die=1-SakugaMath.inside(SakugaMath.clamp((k-0.55)/0.45))
            let ease=SakugaMath.out(k), px=x+vx*ease*life, py=y+vy*ease*life
            let circles=frozen.map { a,d,r,phase,speed in
                (px+cos(a+t*0.9*speed)*d*(0.5+ease*0.9), py+sin(a+t*0.9*speed)*d*(0.5+ease*0.9)-ease*5*speed, r*grow*die*(1+sin(t*9+phase)*0.05))
            }
            p.blob(g,circles,lightX:0.5,arcs:size>6.5,depth:1.5)
        }
    }
    func burst(_ owner: UUID, x: Double, y: Double, radius: Double = 98, spikes: Int = 17, life: Double = 0.48) {
        let jag=(0..<(spikes*2)).map { $0%2==1 ? SakugaMath.random(0.34,0.5) : SakugaMath.random(0.75,1.15) }
        let rot=SakugaMath.random(0,2 * .pi)
        let pins=(0..<8).map { i in (Double(i)/8*2*Double.pi+SakugaMath.random(0,0.5),SakugaMath.random(1.25,1.75),SakugaMath.random(0.03,0.055)) }
        add(owner,life:life) { g,p,k,_ in
            let r=radius*SakugaMath.out(SakugaMath.clamp(k/0.3)), hollow=1+SakugaMath.inside(SakugaMath.clamp((k-0.35)/0.65))*1.3, r0=r*0.6*min(1.9,hollow)
            g.setFillColor(p.accent)
            for (a,l,w) in pins where r*l>r0 {
                g.move(to:CGPoint(x:x+cos(a-w)*r0,y:y+sin(a-w)*r0)); g.addLine(to:CGPoint(x:x+cos(a)*r*l,y:y+sin(a)*r*l))
                g.addLine(to:CGPoint(x:x+cos(a+w)*r0,y:y+sin(a+w)*r0));g.closePath()
            };g.fillPath()
            func star(_ radius: Double, _ turn: Double)->CGPath {
                let path=CGMutablePath()
                for (i,m) in jag.enumerated() {
                    let a=rot+turn+Double(i)/Double(jag.count)*2*Double.pi, rr=radius*m*(i%2==1 ? hollow:1)
                    let pt=CGPoint(x:x+cos(a)*rr,y:y+sin(a)*rr)
                    if i==0 { path.move(to:pt) } else { path.addLine(to:pt) }
                };path.closeSubpath();return path
            }
            g.addPath(star(r*1.16,0.19));g.setFillColor(p.shade);g.setStrokeColor(p.line);g.setLineWidth(1.2);g.drawPath(using:.fillStroke)
            p.shape(g,star(r*0.84,0),width:1.4)
        }
    }
    func shards(_ owner: UUID, x: Double, y: Double, n: Int = 11, speed: Double = 260,
                size: Double = 9, life: Double = 0.95, direction: Double = -.pi/2,
                arc: Double = 6.28, gravity: Double = 300, delay: Double = 0) {
        for _ in 0..<n {
            let a=direction+SakugaMath.random(-arc,arc)/2, v=speed*SakugaMath.random(0.5,1.15), s=size*SakugaMath.random(0.6,1.4), spin=SakugaMath.random(-7,7)
            let pts:[(Double,Double)]=[(-1.4,0.1),(-0.6,-0.7),(1.2,-0.45),(1.5,0.15),(0.4,0.75)].map { ($0.0*SakugaMath.random(0.8,1.2),$0.1*SakugaMath.random(0.8,1.2)) }
            add(owner,life:life*SakugaMath.random(0.7,1),delay:delay) { g,p,k,t in
                let sc=s*(1-SakugaMath.inside(SakugaMath.clamp((k-0.6)/0.4)))
                g.translateBy(x:x+cos(a)*v*t,y:y+sin(a)*v*t+gravity*t*t);g.rotate(by:spin*t+a)
                let path=CGMutablePath()
                for (i,pt) in pts.enumerated() { let point=CGPoint(x:pt.0*sc,y:pt.1*sc);if i==0 {path.move(to:point)} else {path.addLine(to:point)} };path.closeSubpath()
                p.shape(g,path,width:1.1,offset:sc*0.45)
                if sc>2.5 {g.setStrokeColor(p.line);g.setLineWidth(0.9);g.move(to:CGPoint(x:pts[1].0*sc,y:pts[1].1*sc));g.addLine(to:CGPoint(x:pts[4].0*sc,y:pts[4].1*sc));g.strokePath()}
            }
        }
    }
    func donut(_ owner: UUID, x: Double, y: Double, radius: Double, vx: Double, vy: Double, life: Double, delay: Double) {
        let phase=SakugaMath.random(0,2 * .pi), tilt = -0.25
        add(owner,life:life,delay:delay) { g,p,k,t in
            let s=SakugaMath.back(SakugaMath.clamp(t/0.22))*(1-SakugaMath.inside(SakugaMath.clamp((k-0.6)/0.4)))
            guard s>=0.03 else{return}
            let px=x+vx*SakugaMath.out(k)*life, py=y+vy*SakugaMath.out(k)*life, path=CGMutablePath()
            for (m,bump) in [(1.0,0.09),(0.42+0.22*k,0.05)] {
                for i in 0...48 {
                    let a=Double(i)/48*2*Double.pi, rr=radius*s*m*(1+bump*sin(a*9+phase+t*2)), ex=cos(a)*rr, ey=sin(a)*rr*0.52
                    let pt=CGPoint(x:px+ex*cos(tilt)-ey*sin(tilt),y:py+ex*sin(tilt)+ey*cos(tilt))
                    if i==0 {path.move(to:pt)}else{path.addLine(to:pt)}
                };path.closeSubpath()
            }
            g.addPath(path);g.setStrokeColor(p.line);g.setLineWidth(3);g.strokePath()
            g.saveGState();g.addPath(path);g.clip(using:.evenOdd);g.setFillColor(p.shade);g.fill(CGRect(x:-10000,y:-10000,width:20000,height:20000))
            g.translateBy(x:radius*0.06,y:-radius*0.2);g.addPath(path);g.setFillColor(p.fill);g.fillPath(using:.evenOdd);g.restoreGState()
        }
    }
    func wob(_ owner: UUID,x: Double,y: Double,direction: Double,radius: Double = 16,life:Double = 0.45,delay:Double = 0) {
        add(owner,life:life,delay:delay) {g,p,k,_ in
            let width=2.2*(1-k);guard width>=0.2 else{return}
            g.setStrokeColor(p.line);g.setLineWidth(width)
            for d in [0.0,7] {let r=radius+d+SakugaMath.out(k)*8,c=direction>0 ? 0:Double.pi
                g.move(to:CGPoint(x:x-direction*radius+cos(c-0.45)*r,y:y+sin(c-0.45)*r))
                g.addArc(center:CGPoint(x:x-direction*radius,y:y),radius:r,startAngle:c-0.45,endAngle:c+0.45,clockwise:false)
            };g.strokePath()
        }
    }
    func lines(_ owner:UUID,x:Double,y:Double,n:Int = 1,direction:Double = .pi,length:Double = 46,spread:Double = 3,life:Double = 0.3) {
        for _ in 0..<n {
            let o=SakugaMath.random(-spread,spread),l=length*SakugaMath.random(0.5,1.3),d=SakugaMath.random(0,0.25),w=SakugaMath.random(1,2.6)
            add(owner,life:life) {g,p,k,_ in
                let kk=SakugaMath.clamp((k-d)/(1-d)),a=SakugaMath.out(kk),b=SakugaMath.inside(kk),px=x-sin(direction)*o,py=y+cos(direction)*o
                guard kk>0 else{return};g.setStrokeColor(p.line);g.setLineWidth(w*(1-b))
                g.move(to:CGPoint(x:px+cos(direction)*l*b*1.4,y:py+sin(direction)*l*b*1.4))
                g.addLine(to:CGPoint(x:px+cos(direction)*l*(0.2+a*1.2),y:py+sin(direction)*l*(0.2+a*1.2)));g.strokePath()
            }
        }
    }
    func lettering(_ owner:UUID,name:String,x:Double,y:Double,size:Double,life:Double,rotation:Double = -0.12) {
        guard let word=SakugaLettering.words[name] else{return}
        var spring=SakugaSpring(0.2,520,17);spring.target=1
        var last=0.0
        add(owner,life:life) {g,p,k,t in
            let sc=spring.step(t-last)*(1-SakugaMath.inside(SakugaMath.clamp((k-0.86)/0.14)))*size/word.width;last=t
            g.translateBy(x:x+sin(t*31)*0.8,y:y+cos(t*27)*0.8);g.rotate(by:rotation+sin(t*6)*0.03)
            g.scaleBy(x:sc,y:sc);g.translateBy(x:-word.width/2,y:-word.height/2)
            g.setLineJoin(.round);g.addPath(word.path);g.setStrokeColor(p.fill);g.setLineWidth(word.width*0.07);g.strokePath()
            g.addPath(word.path);g.setFillColor(p.ink);g.fillPath()
        }
    }
    func press(_ owner:UUID,rect:CGRect) {
        let x=rect.midX,y=rect.midY
        ticks(owner,x:x,y:rect.minY-6,radius:4,length:14,direction:-.pi/2,life:0.4,fan:0.5)
        wob(owner,x:rect.minX-6,y:y,direction:-1,radius:10,life:0.3);wob(owner,x:rect.maxX+6,y:y,direction:1,radius:10,life:0.3)
        lines(owner,x:x,y:rect.maxY+10,n:3,direction:0,length:16,spread:0.1,life:0.25)
    }
    func impact(_ owner:UUID,rect:CGRect,primary:Bool) {
        clear(owner:owner)
        let x=rect.midX,y=rect.midY
        guard primary else{ticks(owner,x:rect.maxX-8,y:rect.minY-4);return}
        shards(owner,x:x,y:y) // The burst is drawn by the native button back layer.
        for (dx,dy) in [(-1.0,-0.5),(1,-1),(-1,0.9),(1,1)] {
            puff(owner,x:x+dx*(rect.width/2+6),y:y+dy*26,size:SakugaMath.random(12,16),vx:dx*46,vy:dy*30-6,life:SakugaMath.random(0.75,1.05))
        }
        lettering(owner,name:"don",x:x+10,y:y-84,size:176,life:1.05)
        ticks(owner,x:x-96,y:y-70,n:2,radius:4,length:22,direction:-2.4,life:0.45)
        ticks(owner,x:x+110,y:y-60,n:2,radius:4,length:22,direction:-0.7,life:0.45)
        wob(owner,x:rect.minX-8,y:y,direction:-1,delay:0.2);wob(owner,x:rect.maxX+8,y:y,direction:1,delay:0.2)
        donut(owner,x:x+6,y:y-44,radius:30,vx:22,vy:-52,life:1.25,delay:0.2)
        donut(owner,x:x+54,y:y-50,radius:18,vx:34,vy:-40,life:1.1,delay:0.29)
        donut(owner,x:x+86,y:y-46,radius:10,vx:40,vy:-30,life:0.95,delay:0.37)
        for xx in [x-30,x+34] {shards(owner,x:xx,y:y+30,n:2,speed:20,size:6,direction:.pi/2,arc:1,gravity:380,delay:0.2)}
    }
}

@MainActor private enum SakugaLettering {
    struct Word { let width: Double; let height: Double; let path: CGPath }
    static let words: [String:Word] = [
        "don": Word(width:520,height:297,path:parse("M3 290C4 287 6 283 7 281C9 277 18 252 19 248C20 246 19 246 15 250C13 253 11 255 11 254C12 253 15 242 19 230C24 218 30 195 34 180C38 165 43 144 46 133C49 122 51 113 51 113C50 113 50 110 51 107C52 104 52 98 52 94C53 86 57 69 63 54C69 41 69 40 70 41C71 42 72 42 74 40L76 38L75 40C75 43 76 42 85 34C90 28 94 24 95 24C95 24 94 27 92 30C87 40 88 40 100 28C106 22 111 18 111 18C111 18 110 20 109 22C107 28 108 28 114 23C123 15 124 15 122 19C120 21 120 22 121 21C124 20 132 14 136 10C141 5 141 5 136 14C132 23 132 23 135 23C136 22 136 22 135 24C133 29 131 36 132 36C132 36 133 35 135 34C136 32 138 31 138 31C138 31 136 39 132 48C123 71 97 147 98 148C98 148 101 147 105 145C108 144 116 141 122 138C128 136 141 131 150 128C179 117 232 98 234 98C235 98 233 101 229 104C226 108 223 111 223 111C224 111 222 114 219 117C213 124 213 124 216 123C218 123 218 124 214 128C209 133 205 139 204 142C203 143 203 143 205 142C208 140 208 141 204 147C201 150 200 152 201 152C204 151 203 152 197 159C193 163 192 166 194 166C196 166 192 169 182 173C176 175 172 177 170 176C169 176 166 177 163 178C157 180 144 185 143 185C143 185 143 184 144 184C144 183 144 183 143 183C142 183 137 185 132 186C122 189 99 198 90 201L85 204L80 216C73 232 61 258 59 261C57 263 57 263 58 258L58 252L55 255C54 256 52 259 51 260C50 261 49 262 50 261C51 258 48 261 43 267C37 274 36 274 39 268C40 265 41 262 41 262C41 261 36 266 29 273C23 280 18 285 17 285C17 284 18 282 19 279C23 271 22 272 14 281C10 286 5 291 4 292L1 296L3 290ZM223 274C222 274 221 273 220 273C219 273 218 272 218 271C218 266 214 260 212 260C211 261 210 260 210 258C208 251 208 247 208 247C208 246 208 246 207 246C207 246 206 243 207 239C207 234 207 232 206 232C205 233 205 232 206 227C207 225 210 222 214 218C222 213 223 212 220 217C218 221 220 220 233 211C244 203 247 201 243 205C242 207 241 208 241 208C242 210 296 172 333 144C343 137 352 131 353 130C356 129 382 110 397 98C403 94 408 90 408 90C408 91 403 99 397 107C393 112 393 116 396 111C397 111 398 110 398 110C398 111 394 116 390 122C379 135 379 136 382 134C384 133 384 133 383 134C379 140 373 148 372 149C371 151 371 151 381 143C385 140 388 138 389 138C389 138 386 142 382 147C378 151 375 155 375 156C377 158 353 182 344 189C342 191 332 199 323 206C304 222 280 241 277 242C276 242 273 244 269 247C259 255 226 276 225 276C225 276 224 275 223 274ZM373 264C372 264 372 263 372 262C372 261 371 259 370 259C369 257 369 257 370 252C373 244 372 243 370 246C366 249 366 248 369 243C373 237 378 226 378 225C378 222 386 217 398 211C411 204 415 202 413 204C412 205 412 206 412 207C413 207 429 203 432 202C434 201 435 200 429 212C425 222 425 222 432 217C436 214 436 214 428 226C424 231 420 238 418 242L414 249L403 255C397 258 391 261 389 263C384 266 384 266 385 263C385 261 383 261 378 264C375 265 374 265 373 264ZM392 199C392 196 438 54 441 46C444 41 453 28 458 23C463 18 463 18 462 21C461 23 460 25 459 27L458 29L461 27C462 26 467 22 470 19C477 13 477 13 473 21C471 24 470 27 470 27C471 27 476 24 483 20C496 12 497 11 495 14C491 17 494 16 505 9C512 5 517 2 517 2C518 2 515 6 512 10C507 17 500 29 502 29C502 29 504 28 506 26C509 25 511 23 512 23C514 22 514 21 507 32C499 44 497 49 502 44C505 41 504 44 498 55C488 70 483 79 477 92C473 98 470 103 470 104C467 107 455 132 456 131C460 128 459 131 450 145C446 153 438 166 434 174C425 190 425 191 426 184L426 179L420 184C416 188 412 191 411 193C409 196 408 194 410 189C411 185 410 185 405 191C403 193 401 195 401 194C402 191 401 192 396 196C394 199 392 200 392 199ZM226 147C228 140 228 140 226 141C225 141 225 140 227 136C232 128 235 122 234 121C234 120 235 118 237 115C245 103 245 103 242 104C241 105 241 104 244 102C250 96 260 88 264 87C268 86 282 87 281 88C281 89 283 89 285 89C287 89 289 90 289 90C289 91 294 92 299 94C304 95 309 96 309 97C310 98 319 102 325 102C331 103 331 103 326 108C325 110 323 113 323 113C323 114 320 118 316 121C312 125 309 129 309 129C310 129 307 132 304 136L299 142L290 142C279 141 265 142 245 148C235 150 226 152 225 153L223 153L226 147ZM133 121C133 103 157 28 160 39C160 41 161 41 166 35C173 28 174 28 173 32C171 36 172 36 180 32C184 30 188 28 188 29C189 29 192 28 195 26C201 22 202 22 199 29C197 31 196 36 195 39C192 46 167 99 165 101C164 102 164 102 164 100C164 99 163 100 158 104C153 109 153 109 153 107L153 104L149 107C147 108 143 112 139 116C136 120 133 122 133 121ZM180 104C180 97 192 64 203 43C210 29 220 16 218 22L218 25L225 21C231 16 233 15 231 18C226 25 230 23 245 13C251 10 255 7 255 8C255 8 253 12 251 15C246 22 245 25 248 22C251 20 250 22 246 30C241 38 240 39 243 38C245 37 245 36 228 62C212 85 208 91 209 87C209 85 208 84 207 86C206 86 204 88 202 90L198 93L199 90C200 87 198 88 188 98C184 102 180 105 180 104Z")),
        "gogo": Word(width:520,height:288,path:parse("M1 284C1 281 1 274 1 268L2 257L15 253C22 250 32 247 37 246C42 245 46 244 46 243C47 243 50 217 49 216C48 215 31 222 19 228C4 235 6 235 6 231C7 229 7 229 6 229C4 230 4 231 6 220C8 215 9 208 10 206C10 202 10 201 13 201C15 200 24 197 34 194C43 190 51 187 52 187C52 187 52 189 52 192C52 198 53 199 60 196C66 193 79 190 80 190C80 191 79 198 77 207C73 225 70 242 70 254C69 263 72 261 44 270C28 275 18 279 1 288C0 288 0 286 1 284ZM84 281C84 280 85 273 87 263C88 254 89 245 89 243L88 239L102 234C109 232 122 228 129 226C136 224 143 222 143 222C143 221 149 189 149 187C149 185 148 186 133 192C119 197 105 204 97 209L93 211L93 207C94 203 94 202 93 203C91 203 91 202 93 198C98 186 102 173 102 169C102 167 103 166 103 166C109 164 125 159 137 154C145 151 151 149 152 149C152 149 153 152 154 156C154 160 154 163 155 163C155 163 159 161 164 159C171 156 190 152 191 153C191 153 189 164 185 178C179 205 174 231 174 240L174 245L163 248C157 250 148 253 142 255C131 258 101 271 90 278C85 281 84 281 84 281ZM191 269C191 268 192 260 193 251C195 241 196 230 196 225L196 217L200 216C203 215 217 211 233 206C249 200 263 196 265 196C267 195 268 194 269 194C269 193 276 149 276 148C275 147 241 160 230 166C226 168 219 172 214 175C201 182 202 183 205 165C206 159 208 147 209 140L211 126L215 125C217 125 231 121 247 116C263 110 276 106 278 106C280 105 280 105 281 114C281 122 281 123 283 123C284 122 289 120 294 118C307 113 327 109 327 112C327 113 324 125 321 139C312 173 305 212 307 219L307 223L298 226C293 228 283 231 276 232C259 237 209 259 196 267C192 269 192 269 191 269ZM321 255C321 253 333 202 333 201C334 201 333 199 332 197C330 192 331 191 338 191C342 190 357 187 372 184C387 180 404 176 410 175C415 174 420 173 420 172C421 172 433 117 433 115C433 113 430 114 418 118C396 124 369 136 353 146C348 150 344 152 343 152C343 151 343 148 344 144C346 137 346 136 343 138C340 139 340 139 344 124C349 108 352 94 352 88C352 83 353 81 356 81C359 81 381 75 402 69C421 63 436 59 437 59C437 60 437 65 438 70C438 76 439 81 439 82C440 82 446 80 454 77C466 72 469 72 481 70C500 68 498 68 496 73C496 76 493 84 491 92C489 99 485 112 483 119C478 132 470 167 469 178C468 182 467 187 466 191C465 195 465 200 465 203L464 209L455 211C450 212 441 215 435 216C429 218 420 221 415 223C395 228 372 237 353 246C332 257 332 257 332 254C333 251 331 251 326 254C322 257 321 258 321 255ZM55 179L56 164L64 160C69 158 74 156 74 157C74 157 73 164 71 173L67 188L62 191C59 193 56 194 56 194C55 194 55 187 55 179ZM72 188C72 186 78 162 79 161C80 160 93 155 94 155C95 155 93 162 89 173L85 184L79 186C73 188 72 188 72 188ZM157 140C157 130 157 121 156 119C156 116 156 115 159 115C160 114 166 112 171 109C176 107 181 105 181 106C182 106 181 111 179 116C178 122 176 132 175 138C174 145 173 151 173 151C172 151 158 158 158 158C157 158 157 150 157 140ZM178 149C178 146 185 115 186 114C187 113 202 107 204 107C206 107 205 113 199 131L195 146L188 148C184 149 180 150 179 150C179 150 178 150 178 149ZM285 103C285 95 285 84 285 78C285 67 285 67 288 66C293 65 300 63 308 59C320 54 319 54 315 69C311 81 308 93 306 102C305 108 305 109 302 109C301 110 296 112 292 114C288 115 285 117 285 117C284 117 284 111 285 103ZM311 106C311 105 313 97 316 87C318 77 320 68 321 67C321 66 322 65 323 64C325 63 345 56 346 56C348 56 347 62 341 78C332 104 334 102 323 105C318 106 313 107 312 108C312 108 311 107 311 106ZM443 74C442 73 442 15 442 14C443 14 445 13 447 13C450 13 458 10 466 6C474 3 481 0 481 1C482 1 480 10 478 20C475 30 472 45 470 52C469 60 467 66 467 66C466 66 461 68 455 71C442 76 443 75 443 74ZM475 64C475 64 478 52 481 37L487 11L503 5C512 2 519 0 519 1C521 2 505 55 502 59C502 59 497 61 490 62C484 63 478 64 477 65C476 65 475 65 475 64Z")),
    ]
    // Upstream traced art contains only absolute M/L/C/Z operations.
    private static func parse(_ svg: String) -> CGPath {
        let pattern = try! NSRegularExpression(pattern: "[MCLZ]|-?[0-9]+(?:\\.[0-9]+)?")
        let ns=svg as NSString
        let tokens=pattern.matches(in:svg,range:NSRange(location:0,length:ns.length)).map { ns.substring(with:$0.range) }
        var index=0
        func point()->CGPoint { let x=Double(tokens[index])!,y=Double(tokens[index+1])!;index+=2;return CGPoint(x:x,y:y) }
        let path=CGMutablePath()
        while index<tokens.count {
            let command=tokens[index];index+=1
            switch command {
            case "M": path.move(to:point())
            case "L": path.addLine(to:point())
            case "C": let c1=point(),c2=point(),end=point();path.addCurve(to:end,control1:c1,control2:c2)
            case "Z": path.closeSubpath()
            default: preconditionFailure("Unexpected bundled Sakuga path")
            }
        }
        return path
    }
}
#endif
