//
//  GameScene.swift
//  OmatsuriTopia
//
//  Created by Hibiki Tsuboi on 2025/12/21.
//

import SpriteKit
import GameplayKit

// MARK: - GameState
class GameState {
    var score: Int = 0
    var bulletsRemaining: Int = 10
    var bulletsTotal: Int = 10
    var isGameActive: Bool = true
    var targetsDestroyed: Int = 0
}

class GameScene: SKScene {

    var entities = [GKEntity]()
    var graphs = [String : GKGraph]()

    private var lastUpdateTime : TimeInterval = 0

    // ゲーム状態
    private let gameState = GameState()

    // UI要素
    private var scoreLabel: SKLabelNode!
    private var bulletsLabel: SKLabelNode!
    private var crosshair: SKShapeNode!
    private var fireButton: SKShapeNode!
    private var fireButtonLabel: SKLabelNode!
    private var gameOverPanel: SKNode?

    // 的のスポーンレーン（Y座標）
    private var lanes: [CGFloat] = []

    // スポーンタイマー
    private var spawnTimer: TimeInterval = 0
    private let spawnInterval: TimeInterval = 2.0

    override func sceneDidLoad() {
        self.lastUpdateTime = 0
        self.backgroundColor = SKColor(red: 0.15, green: 0.15, blue: 0.3, alpha: 1.0)

        setupLanes()
        setupUI()
        setupCrosshair()
        setupFireButton()
    }

    // MARK: - Setup

    private func setupLanes() {
        // 5本のレーンを作成
        let laneCount = 5
        let topMargin: CGFloat = 150
        let bottomMargin: CGFloat = 150
        let usableHeight = size.height - topMargin - bottomMargin

        for i in 0..<laneCount {
            let y = bottomMargin + (usableHeight / CGFloat(laneCount - 1)) * CGFloat(i)
            lanes.append(y)
        }
    }

    private func setupUI() {
        // スコアラベル（左上）
        scoreLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLabel.fontSize = 32
        scoreLabel.fontColor = .white
        scoreLabel.position = CGPoint(x: 100, y: size.height - 60)
        scoreLabel.horizontalAlignmentMode = .left
        updateScoreLabel()
        addChild(scoreLabel)

        // 弾数ラベル（右上）
        bulletsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        bulletsLabel.fontSize = 32
        bulletsLabel.fontColor = .white
        bulletsLabel.position = CGPoint(x: size.width - 100, y: size.height - 60)
        bulletsLabel.horizontalAlignmentMode = .right
        updateBulletsLabel()
        addChild(bulletsLabel)
    }

    private func setupCrosshair() {
        // 照準器を作成（十字線）
        crosshair = SKShapeNode()

        let outerCircle = SKShapeNode(circleOfRadius: 30)
        outerCircle.strokeColor = .white
        outerCircle.lineWidth = 2
        outerCircle.fillColor = .clear

        let innerCircle = SKShapeNode(circleOfRadius: 3)
        innerCircle.strokeColor = .red
        innerCircle.fillColor = .red

        let horizontalLine = SKShapeNode(rect: CGRect(x: -30, y: -1, width: 60, height: 2))
        horizontalLine.strokeColor = .white
        horizontalLine.fillColor = .white

        let verticalLine = SKShapeNode(rect: CGRect(x: -1, y: -30, width: 2, height: 60))
        verticalLine.strokeColor = .white
        verticalLine.fillColor = .white

        crosshair.addChild(outerCircle)
        crosshair.addChild(innerCircle)
        crosshair.addChild(horizontalLine)
        crosshair.addChild(verticalLine)

        crosshair.position = CGPoint(x: size.width / 2, y: size.height / 2)
        crosshair.zPosition = 100
        addChild(crosshair)
    }

    private func setupFireButton() {
        // 発射ボタン（右下）
        fireButton = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 100, height: 80), cornerRadius: 10)
        fireButton.fillColor = SKColor.systemRed
        fireButton.strokeColor = .white
        fireButton.lineWidth = 3
        fireButton.position = CGPoint(x: size.width - 130, y: 30)
        fireButton.zPosition = 100
        fireButton.name = "fireButton"
        addChild(fireButton)

        fireButtonLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        fireButtonLabel.text = "FIRE"
        fireButtonLabel.fontSize = 24
        fireButtonLabel.fontColor = .white
        fireButtonLabel.position = CGPoint(x: 50, y: 25)
        fireButtonLabel.verticalAlignmentMode = .center
        fireButtonLabel.horizontalAlignmentMode = .center
        fireButton.addChild(fireButtonLabel)
    }

    // MARK: - Game Logic

    private func spawnTarget() {
        guard gameState.isGameActive else { return }

        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let target = TargetEntity.createRandom(in: bounds, lanes: lanes)

        // シーンにスプライトを追加
        if let spriteComponent = target.component(ofType: SpriteComponent.self) {
            addChild(spriteComponent.node)
        }

        entities.append(target)
    }

    private func fire() {
        guard gameState.isGameActive, gameState.bulletsRemaining > 0 else { return }

        // 弾数を減らす
        gameState.bulletsRemaining -= 1
        updateBulletsLabel()

        // 照準器の位置で当たり判定
        let crosshairPos = crosshair.position
        var hitTarget: GKEntity?

        for entity in entities {
            if let spriteComponent = entity.component(ofType: SpriteComponent.self) {
                let sprite = spriteComponent.node
                if sprite.contains(crosshairPos) {
                    hitTarget = entity
                    break
                }
            }
        }

        if let target = hitTarget {
            // 命中！
            if let scoreComponent = target.component(ofType: ScoreComponent.self) {
                gameState.score += scoreComponent.points
                gameState.targetsDestroyed += 1
                updateScoreLabel()
            }

            // 的を削除
            if let spriteComponent = target.component(ofType: SpriteComponent.self) {
                // ヒットエフェクト
                let fadeOut = SKAction.fadeOut(withDuration: 0.2)
                let scaleUp = SKAction.scale(to: 1.5, duration: 0.2)
                let group = SKAction.group([fadeOut, scaleUp])
                spriteComponent.node.run(group) {
                    spriteComponent.node.removeFromParent()
                }
            }

            if let index = entities.firstIndex(where: { $0 === target }) {
                entities.remove(at: index)
            }

            // 発射ボタンのフィードバック
            let originalColor = fireButton.fillColor
            fireButton.fillColor = .systemGreen
            fireButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.1),
                SKAction.run { [weak self] in
                    self?.fireButton.fillColor = originalColor
                }
            ]))
        } else {
            // ミス
            let originalColor = fireButton.fillColor
            fireButton.fillColor = .darkGray
            fireButton.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.1),
                SKAction.run { [weak self] in
                    self?.fireButton.fillColor = originalColor
                }
            ]))
        }

        // 弾切れチェック
        if gameState.bulletsRemaining == 0 {
            endGame()
        }
    }

    private func endGame() {
        gameState.isGameActive = false

        // ゲームオーバーパネルを表示
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 400, height: 300), cornerRadius: 20)
        panel.fillColor = SKColor(white: 0.2, alpha: 0.95)
        panel.strokeColor = .white
        panel.lineWidth = 3
        panel.position = CGPoint(x: size.width / 2 - 200, y: size.height / 2 - 150)
        panel.zPosition = 200

        let titleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        titleLabel.text = "GAME OVER"
        titleLabel.fontSize = 40
        titleLabel.fontColor = .white
        titleLabel.position = CGPoint(x: 200, y: 220)
        titleLabel.horizontalAlignmentMode = .center
        panel.addChild(titleLabel)

        let scoreText = SKLabelNode(fontNamed: "Arial")
        scoreText.text = "Score: \(gameState.score)"
        scoreText.fontSize = 32
        scoreText.fontColor = .white
        scoreText.position = CGPoint(x: 200, y: 160)
        scoreText.horizontalAlignmentMode = .center
        panel.addChild(scoreText)

        let hitsText = SKLabelNode(fontNamed: "Arial")
        hitsText.text = "Hits: \(gameState.targetsDestroyed) / \(gameState.bulletsTotal)"
        hitsText.fontSize = 24
        hitsText.fontColor = .white
        hitsText.position = CGPoint(x: 200, y: 120)
        hitsText.horizontalAlignmentMode = .center
        panel.addChild(hitsText)

        let accuracyPercent = gameState.bulletsTotal > 0 ?
            Int((Double(gameState.targetsDestroyed) / Double(gameState.bulletsTotal)) * 100) : 0
        let accuracyText = SKLabelNode(fontNamed: "Arial")
        accuracyText.text = "Accuracy: \(accuracyPercent)%"
        accuracyText.fontSize = 24
        accuracyText.fontColor = .white
        accuracyText.position = CGPoint(x: 200, y: 90)
        accuracyText.horizontalAlignmentMode = .center
        panel.addChild(accuracyText)

        let restartButton = SKShapeNode(rect: CGRect(x: 100, y: 20, width: 200, height: 50), cornerRadius: 10)
        restartButton.fillColor = .systemGreen
        restartButton.strokeColor = .white
        restartButton.lineWidth = 2
        restartButton.name = "restartButton"

        let restartLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        restartLabel.text = "RESTART"
        restartLabel.fontSize = 24
        restartLabel.fontColor = .white
        restartLabel.position = CGPoint(x: 100, y: 12)
        restartLabel.horizontalAlignmentMode = .center
        restartLabel.verticalAlignmentMode = .center
        restartButton.addChild(restartLabel)
        panel.addChild(restartButton)

        gameOverPanel = panel
        addChild(panel)
    }

    private func restartGame() {
        // ゲームオーバーパネルを削除
        gameOverPanel?.removeFromParent()
        gameOverPanel = nil

        // 全ての的を削除
        for entity in entities {
            if let spriteComponent = entity.component(ofType: SpriteComponent.self) {
                spriteComponent.node.removeFromParent()
            }
        }
        entities.removeAll()

        // ゲーム状態をリセット
        gameState.score = 0
        gameState.bulletsRemaining = gameState.bulletsTotal
        gameState.isGameActive = true
        gameState.targetsDestroyed = 0
        spawnTimer = 0

        // UIを更新
        updateScoreLabel()
        updateBulletsLabel()

        // 照準器を中央に戻す
        crosshair.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func updateScoreLabel() {
        scoreLabel.text = "Score: \(gameState.score)"
    }

    private func updateBulletsLabel() {
        bulletsLabel.text = "Bullets: \(gameState.bulletsRemaining)/\(gameState.bulletsTotal)"
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // 発射ボタンをチェック
        if fireButton.contains(location) {
            fire()
            return
        }

        // リスタートボタンをチェック
        if let panel = gameOverPanel {
            let locationInPanel = touch.location(in: panel)
            if let restartButton = panel.childNode(withName: "restartButton"),
               restartButton.contains(locationInPanel) {
                restartGame()
                return
            }
        }

        // ゲーム中なら照準器を移動
        if gameState.isGameActive {
            moveCrosshair(to: location)
        }
    }

    private func moveCrosshair(to position: CGPoint) {
        let moveAction = SKAction.move(to: position, duration: 0.15)
        moveAction.timingMode = .easeOut
        crosshair.run(moveAction)
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        // 初回の更新時刻を設定
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
        }

        // デルタタイムを計算
        let dt = currentTime - self.lastUpdateTime

        // エンティティを更新
        for entity in self.entities {
            entity.update(deltaTime: dt)
        }

        // 画面外の的を削除
        entities.removeAll { entity in
            guard let spriteComponent = entity.component(ofType: SpriteComponent.self) else { return true }
            let sprite = spriteComponent.node
            let isOffScreen = sprite.position.x < -100 || sprite.position.x > size.width + 100

            if isOffScreen {
                sprite.removeFromParent()
                return true
            }
            return false
        }

        // 的をスポーン
        if gameState.isGameActive {
            spawnTimer += dt
            if spawnTimer >= spawnInterval {
                spawnTarget()
                spawnTimer = 0
            }
        }

        self.lastUpdateTime = currentTime
    }
}
