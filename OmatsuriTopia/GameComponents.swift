//
//  GameComponents.swift
//  OmatsuriTopia
//
//  Created by Claude on 2025/12/21.
//

import SpriteKit
import GameplayKit

// MARK: - SpriteComponent
/// SKSpriteNodeを保持するコンポーネント
class SpriteComponent: GKComponent {
    let node: SKSpriteNode

    init(texture: SKTexture?, color: SKColor, size: CGSize) {
        if let texture = texture {
            node = SKSpriteNode(texture: texture, size: size)
        } else {
            node = SKSpriteNode(color: color, size: size)
        }
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MovementComponent
/// 横移動を処理するコンポーネント
class MovementComponent: GKComponent {
    var speed: CGFloat
    var direction: CGFloat = 1.0 // 1 = 右, -1 = 左
    let bounds: CGRect
    weak var spriteComponent: SpriteComponent?

    init(speed: CGFloat, bounds: CGRect) {
        self.speed = speed
        self.bounds = bounds
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didAddToEntity() {
        spriteComponent = entity?.component(ofType: SpriteComponent.self)
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let sprite = spriteComponent?.node else { return }

        // 横方向に移動
        sprite.position.x += direction * speed * CGFloat(seconds)

        // 画面外に出たら削除マーク（GameSceneで削除処理を行う）
        if sprite.position.x < bounds.minX - 100 || sprite.position.x > bounds.maxX + 100 {
            // エンティティに削除フラグを立てる
            // または、GameSceneがチェックして削除する
        }
    }
}

// MARK: - ScoreComponent
/// 的の得点値を保持するコンポーネント
class ScoreComponent: GKComponent {
    let points: Int

    init(points: Int) {
        self.points = points
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
