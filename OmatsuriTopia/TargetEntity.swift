//
//  TargetEntity.swift
//  OmatsuriTopia
//
//  Created by Claude on 2025/12/21.
//

import SpriteKit
import GameplayKit

// MARK: - TargetType
enum TargetType {
    case small   // 小型: 速い、高得点
    case medium  // 中型: 中速、中得点
    case large   // 大型: 遅い、低得点
    case bonus   // ボーナス: レア、高得点
}

// MARK: - TargetEntity
class TargetEntity: GKEntity {

    init(type: TargetType, position: CGPoint, bounds: CGRect) {
        super.init()

        let (size, speed, points, imageName) = TargetEntity.attributes(for: type)

        // 的の画像を使用
        let texture = SKTexture(imageNamed: imageName)
        let spriteComponent = SpriteComponent(texture: texture, color: .clear, size: size)
        spriteComponent.node.position = position
        addComponent(spriteComponent)

        let movementComponent = MovementComponent(speed: speed, bounds: bounds)
        // ランダムな方向（左または右）
        movementComponent.direction = Bool.random() ? 1.0 : -1.0
        addComponent(movementComponent)

        let scoreComponent = ScoreComponent(points: points)
        addComponent(scoreComponent)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Factory Methods

    /// 的の種類ごとの属性を返す
    /// - Returns: (サイズ, 速度, 得点, 画像名)
    private static func attributes(for type: TargetType) -> (CGSize, CGFloat, Int, String) {
        // 各的タイプに異なる画像を割り当て
        switch type {
        case .small:
            // 小型: 速い、高得点
            return (CGSize(width: 50, height: 67), 300, 100, "Target002")
        case .medium:
            // 中型: 中速、中得点
            return (CGSize(width: 80, height: 107), 200, 50, "Target003")
        case .large:
            // 大型: 遅い、低得点
            return (CGSize(width: 110, height: 148), 120, 20, "Target004")
        case .bonus:
            // ボーナス: レア、高得点
            return (CGSize(width: 70, height: 94), 240, 200, "Target005")
        }
    }

    /// ランダムな的の種類を返す
    static func randomType() -> TargetType {
        let random = Int.random(in: 1...100)
        switch random {
        case 1...10:        // 10%
            return .bonus
        case 11...30:       // 20%
            return .small
        case 31...60:       // 30%
            return .medium
        default:            // 40%
            return .large
        }
    }

    /// ランダムな的エンティティを生成
    static func createRandom(in bounds: CGRect, lanes: [CGFloat]) -> TargetEntity {
        let type = randomType()
        let lane = lanes.randomElement() ?? bounds.midY

        // 左右どちらかから出現
        let fromLeft = Bool.random()
        let xPosition = fromLeft ? bounds.minX - 50 : bounds.maxX + 50
        let position = CGPoint(x: xPosition, y: lane)

        return TargetEntity(type: type, position: position, bounds: bounds)
    }
}
