// Original music bed for update.html (55 s, D major, 105 BPM), synthesized so it carries no
// licensing at all. Bell chimes under the opening hellos, a warm pad from the wordmark, a plucked
// arpeggio, then bass, kick and shaker under the demo, a riser into the end card and a final chord.
// Usage: swiftc -O score.swift -o ../tools/score && ../tools/score <out.wav> [long]
// "long" scores the ~90 s YouTube cut (update.html?cut=long): slow chimes, later downbeat and end card.
import Foundation

let long = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "long"
let sr = 48000.0, total = long ? 92.0 : 55.0
let n = Int(sr * total)
var L = [Float](repeating: 0, count: n), R = [Float](repeating: 0, count: n)
var verbIn = [Float](repeating: 0, count: n)   // mono send into the reverb
var rng = SystemRandomNumberGenerator()
func noise() -> Float { Float.random(in: -1...1, using: &rng) }
func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

func add(_ start: Double, _ samples: [Float], gain: Float, pan: Float = 0, send: Float = 0) {
    let s0 = Int(start * sr), gl = gain * (1 - max(0, pan)), gr = gain * (1 + min(0, pan))
    for (i, v) in samples.enumerated() where s0 + i < n && s0 + i >= 0 {
        L[s0 + i] += v * gl; R[s0 + i] += v * gr; verbIn[s0 + i] += v * gain * send
    }
}

// Soft bell: a few inharmonic partials with a long decay.
func bell(_ f: Double, _ dur: Double) -> [Float] {
    let partials: [(Double, Double, Double)] = [(1, 1, 2.2), (2.0, 0.35, 3.5), (2.76, 0.18, 5), (5.4, 0.06, 8)]
    return (0..<Int(dur * sr)).map { i in
        let t = Double(i) / sr
        let a = min(1, t / 0.004)
        return Float(partials.reduce(0) { $0 + $1.1 * sin(2 * .pi * f * $1.0 * t) * exp(-t * $1.2) } * a)
    }
}

// Warm pad note: soft harmonics, two copies detuned a few cents, slow attack and release.
func pad(_ f: Double, _ dur: Double, detune: Double) -> [Float] {
    let attack = 0.9, release = 1.2, len = Int((dur + release) * sr)
    var lp = 0.0
    return (0..<len).map { i in
        let t = Double(i) / sr
        let env = min(1, t / attack) * (t > dur ? exp(-(t - dur) / release * 3) : 1)
        var s = 0.0
        for h in 1...6 { s += sin(2 * .pi * f * Double(h) * (1 + detune) * t) / pow(Double(h), 1.6) }
        lp += (s - lp) * 0.08            // gentle low-pass for warmth
        return Float(lp * env)
    }
}

// Plucked string (Karplus-Strong).
func pluck(_ f: Double, _ dur: Double) -> [Float] {
    let period = max(2, Int(sr / f))
    var buf = (0..<period).map { _ in noise() }
    for i in 1..<period { buf[i] = (buf[i] + buf[i - 1]) * 0.5 }   // darker attack
    var out = [Float](repeating: 0, count: Int(dur * sr))
    for i in 0..<out.count {
        let j = i % period, k = (i + 1) % period
        out[i] = buf[j]
        buf[j] = (buf[j] + buf[k]) * 0.4985
    }
    return out
}

func kick() -> [Float] {
    var phase = 0.0
    return (0..<Int(0.45 * sr)).map { i in
        let t = Double(i) / sr
        phase += 2 * .pi * (48 + 75 * exp(-t * 28)) / sr
        return Float(sin(phase) * exp(-t * 8))
    }
}

func shaker() -> [Float] {
    var prev: Float = 0
    return (0..<Int(0.09 * sr)).map { i in
        let x = noise(), hp = x - prev; prev = x
        return hp * Float(exp(-Double(i) / sr * 45))
    }
}

func bass(_ f: Double, _ dur: Double) -> [Float] {
    (0..<Int(dur * sr)).map { i in
        let t = Double(i) / sr
        let env = min(1, t / 0.01) * exp(-t * 1.6)
        return Float((sin(2 * .pi * f * t) + 0.25 * sin(4 * .pi * f * t)) * env)
    }
}

// Song map.
let beat = 60.0 / 105, bar = beat * 4, t0 = long ? 15.2 : 3.6
let chords: [[Double]] = [[50, 54, 57, 62], [52, 57, 61, 64], [54, 59, 62, 66], [55, 59, 62, 67]]   // D A Bm G
let roots: [Double] = [38, 45, 47, 43]
let endCard = long ? 86.0 : 45.4, lastBar = Int((endCard - t0) / bar) + 2

// Hellos: one chime per greeting, rising through D major pentatonic.
let chime: [Double] = [74, 76, 78, 81, 83, 86, 88, 90, 93]
// Long cut: one chime per slow hello (every 1.4 s), the last for hola.
let chimeStart = long ? 0.4 : 0.2, chimeStep = long ? 1.4 : 0.36
for (i, m) in chime.enumerated() { add(chimeStart + Double(i) * chimeStep, bell(hz(m), long ? 4 : 2.5), gain: 0.10, pan: i % 2 == 0 ? -0.3 : 0.3, send: 0.5) }
add(t0, bell(hz(62), 4), gain: 0.12, send: 0.6)   // the wordmark lands

for b in 0...lastBar {
    let start = t0 + Double(b) * bar
    guard start < total - 0.5 else { break }
    let ci = (b / 2) % 4, chord = b >= lastBar ? chords[0] : chords[ci]
    let isFinal = b >= lastBar
    // Pad on every second bar (each chord lasts two bars); the final chord rings out.
    if b % 2 == 0 || isFinal {
        let dur = isFinal ? total - start - 1.5 : bar * 2
        for (k, m) in chord.enumerated() {
            add(start, pad(hz(m), dur, detune: 0.0018), gain: 0.05, pan: -0.45 + Double(k) * 0.05 > 0 ? 0 : -0.4, send: 0.35)
            add(start, pad(hz(m), dur, detune: -0.0018), gain: 0.05, pan: 0.4, send: 0.35)
        }
        if isFinal { add(start, bell(hz(74), 5), gain: 0.10, send: 0.6); break }
    }
    // Plucked arpeggio from bar 2 (eighth notes over the chord, an octave up).
    if b >= 2 {
        let pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        let bright = start >= endCard - 0.1
        for (k, p) in pattern.enumerated() {
            let m = chord[p] + 12 + (bright && k % 4 == 3 ? 12 : 0)
            add(start + Double(k) * beat / 2, pluck(hz(m), 1.4), gain: 0.16, pan: k % 2 == 0 ? -0.35 : 0.35, send: 0.4)
        }
    }
    // Bass, kick and shaker under the demo and the end card.
    if b >= 4 {
        add(start, bass(hz(roots[ci]), beat * 1.9), gain: 0.32)
        add(start + beat * 2, bass(hz(roots[ci]), beat * 1.9), gain: 0.26)
        add(start, kick(), gain: 0.30)
        add(start + beat * 2, kick(), gain: 0.22)
        for k in 0..<8 where k % 2 == 1 { add(start + Double(k) * beat / 2, shaker(), gain: 0.07, pan: 0.25) }
    }
}

// Riser into the end card, then a soft impact.
let riseStart = endCard - 1.4
var lp: Float = 0
let riser: [Float] = (0..<Int(1.4 * sr)).map { i in
    let k = Float(i) / Float(1.4 * sr)
    lp += (noise() - lp) * (0.02 + 0.3 * k * k)
    return lp * k * k
}
add(riseStart, riser, gain: 0.35, send: 0.5)
add(endCard, kick(), gain: 0.38)

// Schroeder reverb on the send, mixed back in stereo.
func comb(_ x: [Float], _ d: Int, _ g: Float) -> [Float] {
    var y = [Float](repeating: 0, count: x.count)
    for i in 0..<x.count { y[i] = x[i] + (i >= d ? g * y[i - d] : 0) }
    return y
}
func allpass(_ x: [Float], _ d: Int, _ g: Float) -> [Float] {
    var y = [Float](repeating: 0, count: x.count)
    for i in 0..<x.count { let xd = i >= d ? x[i - d] : 0, yd = i >= d ? y[i - d] : 0; y[i] = -g * x[i] + xd + g * yd }
    return y
}
let combsL = [1557, 1617, 1491, 1422].map { comb(verbIn, $0 * 2, 0.80) }
let combsR = [1277, 1356, 1188, 1116].map { comb(verbIn, $0 * 2, 0.80) }
var wetL = (0..<n).map { i in combsL.reduce(0) { $0 + $1[i] } * 0.25 }
var wetR = (0..<n).map { i in combsR.reduce(0) { $0 + $1[i] } * 0.25 }
wetL = allpass(allpass(wetL, 556, 0.5), 441, 0.5); wetR = allpass(allpass(wetR, 579, 0.5), 464, 0.5)
for i in 0..<n { L[i] += wetL[i] * 0.35; R[i] += wetR[i] * 0.35 }

// Fade the tail and normalize to -3 dBFS.
let fadeFrom = Int((total - 3) * sr)
for i in fadeFrom..<n { let g = Float(n - i) / Float(n - fadeFrom); L[i] *= g; R[i] *= g }
let peak = max(L.map(abs).max()!, R.map(abs).max()!)
let gain = 0.708 / peak

// 16-bit stereo WAV.
var data = Data()
func le<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
data.append("RIFF".data(using: .ascii)!); le(UInt32(36 + n * 4)); data.append("WAVEfmt ".data(using: .ascii)!)
le(UInt32(16)); le(UInt16(1)); le(UInt16(2)); le(UInt32(48000)); le(UInt32(48000 * 4)); le(UInt16(4)); le(UInt16(16))
data.append("data".data(using: .ascii)!); le(UInt32(n * 4))
for i in 0..<n {
    le(Int16(max(-1, min(1, L[i] * gain)) * 32767)); le(Int16(max(-1, min(1, R[i] * gain)) * 32767))
}
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote", CommandLine.arguments[1])
