/*
 * HeadMapView.swift
 * UnicornEEG
 *
 * Top-down topographic head map showing signal quality per electrode.
 * Electrode positions follow the Unicorn Hybrid Black layout (10-20 system):
 *   EEG1=Fz, EEG2=C3, EEG3=Cz, EEG4=C4, EEG5=P3, EEG6=Pz, EEG7=P4, EEG8=Oz
 */

import SwiftUI

struct HeadMapView: View {
    @EnvironmentObject var engine: StreamEngine

    // Electrode positions as (x, y) in 0..1 normalized coordinates.
    // Origin top-left, nose at top. Based on 10-20 standard positions.
    private let electrodePositions: [(x: CGFloat, y: CGFloat, label: String)] = [
        (0.50, 0.22, "Fz"),   // EEG1 — frontal midline
        (0.28, 0.40, "C3"),   // EEG2 — left central
        (0.50, 0.40, "Cz"),   // EEG3 — central midline
        (0.72, 0.40, "C4"),   // EEG4 — right central
        (0.28, 0.62, "P3"),   // EEG5 — left parietal
        (0.50, 0.62, "Pz"),   // EEG6 — parietal midline
        (0.72, 0.62, "P4"),   // EEG7 — right parietal
        (0.50, 0.80, "Oz"),   // EEG8 — occipital midline
    ]

    var body: some View {
        VStack(spacing: 4) {
            Text("Signal Quality")
                .font(.system(size: 11, weight: .semibold))

            TimelineView(.animation(minimumInterval: 0.25)) { _ in
                Canvas { context, size in
                    let qualities = engine.signalQuality
                    let centerX = size.width / 2
                    let centerY = size.height / 2
                    let headRadius = min(size.width, size.height) * 0.42
                    let dotRadius: CGFloat = 10

                    // Draw head outline (oval)
                    let headRect = CGRect(
                        x: centerX - headRadius,
                        y: centerY - headRadius,
                        width: headRadius * 2,
                        height: headRadius * 2
                    )
                    context.stroke(Ellipse().path(in: headRect),
                                   with: .color(.gray.opacity(0.4)), lineWidth: 1.5)

                    // Draw nose triangle at top
                    let noseSize: CGFloat = 8
                    var nose = Path()
                    nose.move(to: CGPoint(x: centerX, y: centerY - headRadius - noseSize))
                    nose.addLine(to: CGPoint(x: centerX - noseSize, y: centerY - headRadius + 2))
                    nose.addLine(to: CGPoint(x: centerX + noseSize, y: centerY - headRadius + 2))
                    nose.closeSubpath()
                    context.stroke(nose, with: .color(.gray.opacity(0.4)), lineWidth: 1.5)

                    // Draw ears
                    let earWidth: CGFloat = 6
                    let earHeight: CGFloat = 18
                    let leftEar = CGRect(x: centerX - headRadius - earWidth,
                                         y: centerY - earHeight / 2,
                                         width: earWidth, height: earHeight)
                    let rightEar = CGRect(x: centerX + headRadius,
                                          y: centerY - earHeight / 2,
                                          width: earWidth, height: earHeight)
                    context.stroke(Ellipse().path(in: leftEar),
                                   with: .color(.gray.opacity(0.4)), lineWidth: 1)
                    context.stroke(Ellipse().path(in: rightEar),
                                   with: .color(.gray.opacity(0.4)), lineWidth: 1)

                    // Draw electrodes
                    for (i, pos) in electrodePositions.enumerated() {
                        let x = centerX + (pos.x - 0.5) * headRadius * 2
                        let y = centerY + (pos.y - 0.5) * headRadius * 2

                        let quality = i < qualities.count ? qualities[i].quality : .unknown
                        let color = qualityColor(quality)

                        // Filled circle
                        let dotRect = CGRect(x: x - dotRadius, y: y - dotRadius,
                                             width: dotRadius * 2, height: dotRadius * 2)
                        context.fill(Circle().path(in: dotRect), with: .color(color))
                        context.stroke(Circle().path(in: dotRect),
                                       with: .color(color.opacity(0.8)), lineWidth: 1)

                        // Channel label
                        let label = Text(pos.label)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                        context.draw(label, at: CGPoint(x: x, y: y))

                        // RMS label below dot — human-readable
                        if i < qualities.count {
                            let rms = qualities[i].rms
                            let rmsStr: String
                            if rms > 500 {
                                rmsStr = ">500µV"
                            } else if rms < 1 {
                                rmsStr = "<1µV"
                            } else {
                                rmsStr = String(format: "%.0fµV", rms)
                            }
                            let rmsText = Text(rmsStr)
                                .font(.system(size: 7))
                                .foregroundColor(color.opacity(0.9))
                            context.draw(rmsText, at: CGPoint(x: x, y: y + dotRadius + 7))
                        }
                    }
                }
                .frame(minHeight: 130)
            }

            // Legend
            VStack(spacing: 2) {
                HStack(spacing: 10) {
                    legendDot(color: .green, label: "5–150µV")
                    legendDot(color: .yellow, label: "1–500µV")
                    legendDot(color: .red, label: ">500µV")
                }
            }
            .font(.system(size: 8))
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 8)
    }

    private func qualityColor(_ quality: SignalQuality) -> Color {
        switch quality {
        case .good: return .green
        case .fair: return .yellow
        case .bad: return .red
        case .unknown: return .gray
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundColor(.secondary)
        }
    }
}
