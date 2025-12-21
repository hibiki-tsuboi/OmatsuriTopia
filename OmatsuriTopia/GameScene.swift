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
    private var scoreIcon: SKShapeNode!
    private var bulletsLabel: SKLabelNode!
    private var bulletsIcon: SKNode!
    private var crosshair: SKShapeNode!
    private var fireButton: SKShapeNode!
    private var gameOverPanel: SKNode?

    // 的のスポーンレーン（Y座標）
    private var lanes: [CGFloat] = []

    // スポーンタイマー
    private var spawnTimer: TimeInterval = 0
    private let spawnInterval: TimeInterval = 1.0

    override func sceneDidLoad() {
        self.lastUpdateTime = 0

        // お祭りっぽい背景（夜空＋提灯の明かりをイメージ）
        setupFestivalBackground()

        setupLanes()
        setupUI()
        setupCrosshair()
        setupFireButton()
    }

    private func setupFestivalBackground() {
        // 背景画像を設定
        let background = SKSpriteNode(imageNamed: "Background")
        background.position = CGPoint(x: size.width / 2, y: size.height / 2)
        background.zPosition = -10

        // 画面サイズに合わせて拡大縮小
        let scaleX = size.width / background.size.width
        let scaleY = size.height / background.size.height
        let scale = max(scaleX, scaleY)
        background.setScale(scale)

        addChild(background)

        // 装飾用の提灯を追加
        addLanterns()
    }

    private func addLanterns() {
        // 上部に提灯風の装飾を配置
        let lanternCount = 8
        let spacing = size.width / CGFloat(lanternCount)

        for i in 0..<lanternCount {
            let lantern = SKShapeNode(circleOfRadius: 15)
            lantern.fillColor = i % 2 == 0 ? SKColor.systemRed : SKColor.systemYellow
            lantern.strokeColor = SKColor.systemOrange
            lantern.lineWidth = 2
            lantern.position = CGPoint(
                x: spacing * CGFloat(i) + spacing / 2,
                y: size.height - 30
            )
            lantern.alpha = 0.7
            lantern.zPosition = -1

            // ゆらゆら揺れるアニメーション
            let sway = SKAction.sequence([
                SKAction.moveBy(x: 0, y: -5, duration: 1.0),
                SKAction.moveBy(x: 0, y: 5, duration: 1.0)
            ])
            lantern.run(SKAction.repeatForever(sway))

            addChild(lantern)
        }
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
        // スコア表示用の背景パネル（左上）
        let scorePanel = SKShapeNode(rect: CGRect(x: 10, y: size.height - 90, width: 180, height: 70), cornerRadius: 15)
        scorePanel.fillColor = SKColor(white: 0.0, alpha: 0.7)
        scorePanel.strokeColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        scorePanel.lineWidth = 3
        scorePanel.zPosition = 5
        addChild(scorePanel)

        // スコアアイコン（星）+ 数字
        scoreIcon = createStarIcon()
        scoreIcon.position = CGPoint(x: 30, y: size.height - 50)
        scoreIcon.zPosition = 10
        addChild(scoreIcon)

        scoreLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLabel.fontSize = 40
        scoreLabel.fontColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)  // ゴールド
        scoreLabel.position = CGPoint(x: 70, y: size.height - 60)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.zPosition = 10
        updateScoreLabel()
        addChild(scoreLabel)

        // 弾数表示用の背景パネル（右上）
        let bulletsPanel = SKShapeNode(rect: CGRect(x: size.width - 160, y: size.height - 90, width: 150, height: 70), cornerRadius: 15)
        bulletsPanel.fillColor = SKColor(white: 0.0, alpha: 0.7)
        bulletsPanel.strokeColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        bulletsPanel.lineWidth = 3
        bulletsPanel.zPosition = 5
        addChild(bulletsPanel)

        // 弾丸アイコン + 数字
        bulletsIcon = createBulletIcons()
        bulletsIcon.position = CGPoint(x: size.width - 30, y: size.height - 50)
        bulletsIcon.zPosition = 10
        addChild(bulletsIcon)

        bulletsLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        bulletsLabel.fontSize = 40
        bulletsLabel.fontColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)  // 赤
        bulletsLabel.position = CGPoint(x: size.width - 80, y: size.height - 60)
        bulletsLabel.horizontalAlignmentMode = .right
        bulletsLabel.zPosition = 10
        updateBulletsLabel()
        addChild(bulletsLabel)
    }

    private func createStarIcon() -> SKShapeNode {
        // 星型のアイコン
        let path = CGMutablePath()
        let points: [(CGFloat, CGFloat)] = [
            (0, 15),      // 上
            (4, 5),       // 右上内側
            (14, 5),      // 右上
            (7, -2),      // 右内側
            (10, -12),    // 右下
            (0, -6),      // 下内側
            (-10, -12),   // 左下
            (-7, -2),     // 左内側
            (-14, 5),     // 左上
            (-4, 5)       // 左上内側
        ]

        path.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for i in 1..<points.count {
            path.addLine(to: CGPoint(x: points[i].0, y: points[i].1))
        }
        path.closeSubpath()

        let star = SKShapeNode(path: path)
        star.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)  // ゴールド
        star.strokeColor = SKColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0)
        star.lineWidth = 2
        star.zPosition = 10

        return star
    }

    private func createBulletIcons() -> SKNode {
        // 弾丸のアイコン（3つ横並び）
        let container = SKNode()

        for i in 0..<3 {
            let bullet = SKShapeNode(ellipseOf: CGSize(width: 8, height: 20))
            bullet.fillColor = SKColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0)  // 茶色
            bullet.strokeColor = SKColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 1.0)
            bullet.lineWidth = 1.5
            bullet.position = CGPoint(x: -CGFloat(i) * 12, y: 0)
            container.addChild(bullet)
        }

        return container
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
        // 発射ボタン（右下、ターゲットマークのアイコン）
        let buttonSize: CGFloat = 100
        let margin: CGFloat = 20

        fireButton = SKShapeNode(circleOfRadius: buttonSize / 2)
        fireButton.fillColor = SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)  // 明るい赤
        fireButton.strokeColor = SKColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)  // 濃い赤で縁取り
        fireButton.lineWidth = 5
        fireButton.position = CGPoint(x: size.width - buttonSize / 2 - margin, y: buttonSize / 2 + margin)
        fireButton.zPosition = 100
        fireButton.name = "fireButton"
        addChild(fireButton)

        // ターゲットマークを追加
        let targetIcon = createTargetIcon(size: 60)
        targetIcon.position = CGPoint(x: 0, y: 0)
        fireButton.addChild(targetIcon)
    }

    private func createTargetIcon(size: CGFloat) -> SKNode {
        let container = SKNode()

        // 外側の円
        let outerCircle = SKShapeNode(circleOfRadius: size / 2)
        outerCircle.strokeColor = .white
        outerCircle.lineWidth = 4
        outerCircle.fillColor = .clear
        container.addChild(outerCircle)

        // 中間の円
        let middleCircle = SKShapeNode(circleOfRadius: size / 3)
        middleCircle.strokeColor = .white
        middleCircle.lineWidth = 3
        middleCircle.fillColor = .clear
        container.addChild(middleCircle)

        // 中心の円
        let innerCircle = SKShapeNode(circleOfRadius: size / 6)
        innerCircle.fillColor = .white
        innerCircle.strokeColor = .white
        innerCircle.lineWidth = 2
        container.addChild(innerCircle)

        // 十字線
        let horizontalLine = SKShapeNode(rect: CGRect(x: -size / 2, y: -2, width: size, height: 4))
        horizontalLine.fillColor = .white
        horizontalLine.strokeColor = .clear
        container.addChild(horizontalLine)

        let verticalLine = SKShapeNode(rect: CGRect(x: -2, y: -size / 2, width: 4, height: size))
        verticalLine.fillColor = .white
        verticalLine.strokeColor = .clear
        container.addChild(verticalLine)

        return container
    }

    // MARK: - Game Logic

    private func spawnTarget() {
        guard gameState.isGameActive else { return }

        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)

        // 一度に2-3個の的をランダムに生成
        let targetCount = Int.random(in: 2...3)
        for _ in 0..<targetCount {
            let target = TargetEntity.createRandom(in: bounds, lanes: lanes)

            // シーンにスプライトを追加
            if let spriteComponent = target.component(ofType: SpriteComponent.self) {
                addChild(spriteComponent.node)
            }

            entities.append(target)
        }
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
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 500, height: 350), cornerRadius: 30)
        panel.fillColor = SKColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 0.95)
        panel.strokeColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        panel.lineWidth = 5
        panel.position = CGPoint(x: size.width / 2 - 250, y: size.height / 2 - 175)
        panel.zPosition = 200

        // 大きな星アイコン（タイトル代わり）
        let bigStar = createStarIcon()
        bigStar.setScale(3.0)
        bigStar.position = CGPoint(x: 250, y: 270)
        panel.addChild(bigStar)

        // スコアアイコン + 数字
        let scoreIcon = createStarIcon()
        scoreIcon.position = CGPoint(x: 150, y: 190)
        panel.addChild(scoreIcon)

        let scoreNum = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreNum.text = "\(gameState.score)"
        scoreNum.fontSize = 50
        scoreNum.fontColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        scoreNum.position = CGPoint(x: 250, y: 175)
        scoreNum.horizontalAlignmentMode = .center
        panel.addChild(scoreNum)

        // 的中アイコン + 数字
        let targetHitIcon = createTargetIcon(size: 30)
        targetHitIcon.position = CGPoint(x: 150, y: 120)
        panel.addChild(targetHitIcon)

        let hitsNum = SKLabelNode(fontNamed: "Arial-BoldMT")
        hitsNum.text = "\(gameState.targetsDestroyed) / \(gameState.bulletsTotal)"
        hitsNum.fontSize = 40
        hitsNum.fontColor = .white
        hitsNum.position = CGPoint(x: 280, y: 105)
        hitsNum.horizontalAlignmentMode = .center
        panel.addChild(hitsNum)

        // 命中率
        let accuracyPercent = gameState.bulletsTotal > 0 ?
            Int((Double(gameState.targetsDestroyed) / Double(gameState.bulletsTotal)) * 100) : 0
        let accuracyNum = SKLabelNode(fontNamed: "Arial-BoldMT")
        accuracyNum.text = "\(accuracyPercent)%"
        accuracyNum.fontSize = 45
        accuracyNum.fontColor = accuracyPercent >= 70 ? SKColor(red: 0.2, green: 1.0, blue: 0.2, alpha: 1.0) : .white
        accuracyNum.position = CGPoint(x: 250, y: 45)
        accuracyNum.horizontalAlignmentMode = .center
        panel.addChild(accuracyNum)

        // リスタートボタン（丸いボタンにリプレイアイコン）
        let restartButton = SKShapeNode(circleOfRadius: 40)
        restartButton.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
        restartButton.strokeColor = .white
        restartButton.lineWidth = 3
        restartButton.position = CGPoint(x: 250, y: -30)
        restartButton.name = "restartButton"

        // リプレイアイコン（円形矢印）
        let replayIcon = createReplayIcon()
        replayIcon.position = CGPoint(x: 0, y: 0)
        restartButton.addChild(replayIcon)
        panel.addChild(restartButton)

        gameOverPanel = panel
        addChild(panel)
    }

    private func createReplayIcon() -> SKNode {
        let container = SKNode()

        // 円形矢印（簡易版）
        let arrow = SKShapeNode()
        let path = CGMutablePath()

        // 円弧を描く
        path.addArc(center: .zero, radius: 20, startAngle: .pi / 4, endAngle: .pi * 1.75, clockwise: false)

        arrow.path = path
        arrow.strokeColor = .white
        arrow.lineWidth = 4
        arrow.fillColor = .clear

        // 矢印の先端
        let arrowHead = SKShapeNode()
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: -15, y: 15))
        arrowPath.addLine(to: CGPoint(x: -5, y: 20))
        arrowPath.addLine(to: CGPoint(x: -10, y: 10))
        arrowHead.path = arrowPath
        arrowHead.strokeColor = .white
        arrowHead.lineWidth = 4

        container.addChild(arrow)
        container.addChild(arrowHead)

        return container
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
        scoreLabel.text = "\(gameState.score)"
    }

    private func updateBulletsLabel() {
        bulletsLabel.text = "\(gameState.bulletsRemaining)"
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

        // ゲーム中ならスワイプで照準器を移動開始
        // touchesMovedで実際の移動を処理
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // ゲーム中で、発射ボタンやゲームオーバーパネル以外ならスコープを移動
        if gameState.isGameActive && !fireButton.contains(location) {
            moveCrosshairDirect(to: location)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 必要に応じて処理を追加
    }

    private func moveCrosshairDirect(to position: CGPoint) {
        // 画面内に制限
        let clampedX = max(30, min(size.width - 30, position.x))
        let clampedY = max(30, min(size.height - 30, position.y))
        crosshair.position = CGPoint(x: clampedX, y: clampedY)
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
