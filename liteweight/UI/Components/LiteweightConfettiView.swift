import SwiftUI
import UIKit

/// One render-server burst of the TEMPORARY brand plates; callers skip it under Reduce Motion.
struct LiteweightConfettiView: UIViewRepresentable {
    var heldElapsed: TimeInterval? = nil

    private struct Piece {
        let x: Double
        let delay: Double
        let travel: Double
        let drift: Double
        let sway: Double
        let spin: Double
        let size: CGSize
        let color: Color

        func position(progress: Double, size: CGSize) -> CGPoint {
            let t = progress * (LiteweightConfettiView.duration - delay)
            return CGPoint(x: CGFloat(x) * size.width + CGFloat(sin(t * sway) * drift),
                           y: -16 + CGFloat(progress * travel) * size.height * 0.4)
        }
    }

    private static let duration: TimeInterval = 2.5
    private static let pieces: [Piece] = {
        let colors = [LiteweightTheme.plateRed, LiteweightTheme.plateBlue, LiteweightTheme.plateYellow]
        return (0..<54).map { index in
            Piece(x: .random(in: 0.02...0.98), delay: .random(in: 0...0.45), travel: .random(in: 0.7...1.15),
                  drift: .random(in: 6...22), sway: .random(in: 2...5), spin: .random(in: -7...7),
                  size: CGSize(width: .random(in: 5...7), height: .random(in: 11...16)),
                  color: colors[index % colors.count])
        }
    }()

    func makeUIView(context: Context) -> ConfettiView { ConfettiView() }

    func updateUIView(_ view: ConfettiView, context: Context) {
        view.update(heldElapsed: heldElapsed, environment: context.environment)
    }

    final class ConfettiView: UIView {
        private let plates: [CALayer] = LiteweightConfettiView.pieces.map { piece in
            let plate = CALayer()
            plate.bounds = CGRect(origin: .zero, size: piece.size)
            plate.cornerRadius = 1.5
            plate.opacity = 0
            return plate
        }
        private var heldElapsed: TimeInterval?
        private var renderedElapsed: TimeInterval?
        private var renderedSize: CGSize = .zero
        private var hasRendered = false
        private var startTime: CFTimeInterval?
        private var colorTraits = UITraitCollection()

        init() {
            super.init(frame: .zero)
            isOpaque = false
            clipsToBounds = true
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            plates.forEach { layer.addSublayer($0) }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            renderIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                plates.forEach { $0.removeAllAnimations() }
                hasRendered = false
                startTime = nil
            } else {
                renderIfNeeded()
            }
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateColors()
        }

        func update(heldElapsed: TimeInterval?, environment: EnvironmentValues) {
            self.heldElapsed = heldElapsed
            colorTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: environment.colorScheme == .dark ? .dark : .light),
                UITraitCollection(accessibilityContrast: environment.colorSchemeContrast == .increased ? .high : .normal),
                UITraitCollection(displayScale: environment.displayScale)
            ])
            updateColors()
            renderIfNeeded()
        }

        private func updateColors() {
            let traits = UITraitCollection(traitsFrom: [traitCollection, colorTraits])
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (piece, plate) in zip(LiteweightConfettiView.pieces, plates) {
                plate.backgroundColor = UIColor(piece.color).resolvedColor(with: traits).cgColor
                plate.contentsScale = traits.displayScale
            }
            CATransaction.commit()
        }

        private func renderIfNeeded() {
            guard window != nil, bounds.width > 0, bounds.height > 0,
                  !hasRendered || renderedSize != bounds.size || renderedElapsed != heldElapsed else { return }
            let now = CACurrentMediaTime()
            if heldElapsed == nil, startTime == nil { startTime = now }
            hasRendered = true
            renderedSize = bounds.size
            renderedElapsed = heldElapsed

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (piece, plate) in zip(LiteweightConfettiView.pieces, plates) {
                plate.removeAllAnimations()
                let life = LiteweightConfettiView.duration - piece.delay
                if let heldElapsed {
                    let t = heldElapsed - piece.delay
                    let progress = t / life
                    guard t > 0, progress < 1 else {
                        plate.opacity = 0
                        continue
                    }
                    plate.position = piece.position(progress: progress, size: bounds.size)
                    plate.transform = CATransform3DMakeRotation(CGFloat(t * piece.spin), 0, 0, 1)
                    plate.opacity = Float(progress > 0.7 ? (1 - progress) / 0.3 : 1)
                } else if let startTime {
                    plate.position = piece.position(progress: 1, size: bounds.size)
                    plate.transform = CATransform3DMakeRotation(CGFloat(life * piece.spin), 0, 0, 1)
                    plate.opacity = 0
                    guard now < startTime + LiteweightConfettiView.duration else { continue }

                    let position = CAKeyframeAnimation(keyPath: "position")
                    position.values = (0...30).map { index in
                        NSValue(cgPoint: piece.position(progress: Double(index) / 30, size: bounds.size))
                    }
                    position.calculationMode = .linear
                    let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                    rotation.values = [0, life * piece.spin]
                    rotation.calculationMode = .linear
                    let opacity = CAKeyframeAnimation(keyPath: "opacity")
                    opacity.values = [1, 1, 0]
                    opacity.keyTimes = [0, 0.7, 1]
                    opacity.calculationMode = .linear
                    let animations = [position, rotation, opacity]
                    animations.forEach { $0.duration = life }

                    let burst = CAAnimationGroup()
                    burst.animations = animations
                    burst.duration = life
                    burst.beginTime = plate.convertTime(startTime + piece.delay, from: nil)
                    burst.timingFunction = CAMediaTimingFunction(name: .linear)
                    burst.fillMode = .backwards
                    burst.isRemovedOnCompletion = true
                    burst.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
                    plate.add(burst, forKey: "confetti")
                }
            }
            CATransaction.commit()
        }
    }
}
