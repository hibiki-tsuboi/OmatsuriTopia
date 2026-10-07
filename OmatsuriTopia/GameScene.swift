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
    var bulletsRemaining: Int = GameRules.ammunition
    var bulletsTotal: Int = GameRules.ammunition
    var isGameActive: Bool = true
    var targetsDestroyed: Int = 0
    var isLoaded: Bool = true  // 弾が装填されているか
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
    private var reloadButton: SKShapeNode!
    var onFinish: ((GameResult) -> Void)?
    private var timerLabel: SKLabelNode!
    private let gameClock = ContinuousClock()
    private var startedAt: ContinuousClock.Instant?
    private var shots: [ShotRecord] = []
    private var isReloading = false
    private var hasSetUp = false

    private var elapsedMs: Int {
        guard let startedAt else { return 0 }
        let elapsed = startedAt.duration(to: gameClock.now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1_000_000_000_000_000
        return min(Int(GameRules.duration * 1000), max(0, Int(milliseconds)))
    }

    // 的のスポーンレーン（Y座標）
    private var lanes: [CGFloat] = []

    // スポーンタイマー
    private var spawnTimer: TimeInterval = 0
    private let spawnInterval: TimeInterval = 1.0

    override func didMove(to view: SKView) {
        guard !hasSetUp else { return }
        hasSetUp = true
        startedAt = gameClock.now
        self.lastUpdateTime = 0

        // お祭りっぽい背景（夜空＋提灯の明かりをイメージ）
        setupFestivalBackground()

        setupLanes()
        setupUI()
        setupCrosshair()
        setupFireButton()
        setupReloadButton()
        timerLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        timerLabel.fontSize = 26
        timerLabel.position = CGPoint(x: size.width / 2, y: size.height - 60)
        timerLabel.zPosition = 20
        timerLabel.text = "60秒"
        addChild(timerLabel)
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
        // スコア表示用の背景パネル（左上）- シンプルなゲームUI
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
        let bulletsPanel = SKShapeNode(rect: CGRect(x: size.width - 200, y: size.height - 90, width: 190, height: 70), cornerRadius: 15)
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

    private func setupReloadButton() {
        // リロードボタン（発射ボタンの左側）
        let buttonSize: CGFloat = 100
        let margin: CGFloat = 20
        let spacing: CGFloat = 20

        reloadButton = SKShapeNode(circleOfRadius: buttonSize / 2)
        // 初期状態は装填済みなのでグレーに設定
        reloadButton.fillColor = SKColor(white: 0.4, alpha: 1.0)
        reloadButton.strokeColor = SKColor(white: 0.2, alpha: 1.0)
        reloadButton.lineWidth = 5
        // 発射ボタンの左側に配置
        reloadButton.position = CGPoint(x: size.width - buttonSize / 2 - margin - buttonSize - spacing, y: buttonSize / 2 + margin)
        reloadButton.zPosition = 100
        reloadButton.name = "reloadButton"
        addChild(reloadButton)

        // リロードアイコン（ブラウザのリロードのような円形矢印）を追加
        let reloadIcon = createReloadIcon(size: 55)
        reloadIcon.position = CGPoint(x: 0, y: 0)
        reloadButton.addChild(reloadIcon)
    }

    private func createReloadIcon(size: CGFloat) -> SKNode {
        let container = SKNode()
        let radius = size / 2.2
        
        // 円弧を描く (真上に明確な隙間を作る)
        let path = CGMutablePath()
        let startAngle: CGFloat = CGFloat.pi * 0.25 // 尻尾の開始位置 (より右側に移動)
        let endAngle: CGFloat = CGFloat.pi * 0.5    // 先端の位置 (真上)
        
        // 時計回り(clockwise: true)で描画し、真上に隙間を確保
        path.addArc(center: .zero, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        
        let arc = SKShapeNode(path: path)
        arc.strokeColor = .white
        arc.lineWidth = 9
        arc.lineCap = .round
        container.addChild(arc)
        
        // 矢印の先端 (真上に配置)
        let arrowSize = size / 3.5
        let tipX: CGFloat = 0
        let tipY: CGFloat = radius
        
        let arrowPath = CGMutablePath()
        // 右向きの矢印
        arrowPath.move(to: CGPoint(x: tipX - arrowSize * 0.3, y: tipY + arrowSize * 0.5)) // 左上
        arrowPath.addLine(to: CGPoint(x: tipX + arrowSize * 0.7, y: tipY))               // 右（先端）
        arrowPath.addLine(to: CGPoint(x: tipX - arrowSize * 0.3, y: tipY - arrowSize * 0.5)) // 左下
        arrowPath.closeSubpath()
        
        let arrowHead = SKShapeNode(path: arrowPath)
        arrowHead.fillColor = .white
        arrowHead.strokeColor = .clear
        container.addChild(arrowHead)
        
        return container
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
        guard gameState.isGameActive, gameState.bulletsRemaining > 0, gameState.isLoaded else { return }
        let shotTime = elapsedMs
        guard shotTime < Int(GameRules.duration * 1000) else { endGame(); return }
        guard shots.last.map({ shotTime - $0.offsetMs >= 400 }) ?? true else { return }
        var points = 0

        // 弾数を減らす
        gameState.bulletsRemaining -= 1
        updateBulletsLabel()

        // 装填状態を解除
        gameState.isLoaded = false
        updateReloadButtonState()

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
            if let scoreComponent = target.component(ofType: ScoreComponent.self),
               let spriteComponent = target.component(ofType: SpriteComponent.self) {
                // 獲得した点数を的の位置に表示
                showPointsLabel(points: scoreComponent.points, at: spriteComponent.node.position)

                points = scoreComponent.points
                gameState.score += scoreComponent.points
                gameState.targetsDestroyed += 1
                updateScoreLabel()
            }

            // 的を削除
            if let spriteComponent = target.component(ofType: SpriteComponent.self) {
                // ヒットエフェクト：射的らしく後ろに飛ぶアニメーション
                let fadeOut = SKAction.fadeOut(withDuration: 0.5)
                let scaleDown = SKAction.scale(to: 0.2, duration: 0.5)  // 小さくなって奥に飛ぶ
                let rotate = SKAction.rotate(byAngle: CGFloat.pi * 2, duration: 0.5)  // 1回転
                let moveBack = SKAction.moveBy(x: 0, y: 100, duration: 0.5)  // 上（奥）に移動

                let group = SKAction.group([fadeOut, scaleDown, rotate, moveBack])
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

        shots.append(ShotRecord(offsetMs: shotTime, points: points))

        // 弾切れチェック
        if gameState.bulletsRemaining == 0 {
            endGame()
        }
    }

    private func endGame() {
        guard gameState.isGameActive else { return }
        gameState.isGameActive = false
        let result = GameResult(id: UUID(), score: gameState.score, hits: gameState.targetsDestroyed,
                                elapsedMs: elapsedMs, shots: shots, playedAt: Date())
        isPaused = true
        let completion = onFinish
        onFinish = nil
        completion?(result)
    }

    private func reload() {
        guard gameState.isGameActive, !gameState.isLoaded, !isReloading else { return }
        isReloading = true

        // リロードアニメーション（アイコンを回転させる）
        if let icon = reloadButton.children.first {
            let rotate = SKAction.rotate(byAngle: -CGFloat.pi * 2, duration: 0.4)
            icon.run(rotate)
        }

        // 装填状態にする
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.4),
            SKAction.run { [weak self] in
                guard let self else { return }
                self.isReloading = false
                self.gameState.isLoaded = true
                self.updateReloadButtonState()
            }
        ]))
    }

    private func updateReloadButtonState() {
        if gameState.isLoaded {
            // 装填済み：グレー（リロード不要）
            reloadButton.fillColor = SKColor(white: 0.4, alpha: 1.0)
            reloadButton.strokeColor = SKColor(white: 0.2, alpha: 1.0)
        } else {
            // 未装填：緑色（リロードを促す）
            reloadButton.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
            reloadButton.strokeColor = SKColor(red: 0.1, green: 0.6, blue: 0.1, alpha: 1.0)
        }
    }

    private func updateScoreLabel() {
        scoreLabel.text = "\(gameState.score)"
    }

    private func updateBulletsLabel() {
        bulletsLabel.text = "\(gameState.bulletsRemaining)/\(gameState.bulletsTotal)"
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

        // リロードボタンをチェック
        if reloadButton.contains(location) {
            reload()
            return
        }

        // ゲーム中ならスワイプで照準器を移動開始
        // touchesMovedで実際の移動を処理
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // ゲーム中で、発射ボタンやリロードボタン以外ならスコープを移動
        if gameState.isGameActive && !fireButton.contains(location) && !reloadButton.contains(location) {
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
        guard gameState.isGameActive else { return }
        let remaining = max(0, GameRules.duration - Double(elapsedMs) / 1000)
        timerLabel.text = "\(Int(ceil(remaining)))秒"
        timerLabel.fontColor = remaining <= 10 ? .systemOrange : .white
        if remaining <= 0 { endGame(); return }

        // 初回の更新時刻を設定
        if (self.lastUpdateTime == 0) {
            self.lastUpdateTime = currentTime
        }

        // デルタタイムを計算
        let dt = min(currentTime - self.lastUpdateTime, 0.1)

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

    // MARK: - Visual Effects

    /// 的を射った時に獲得した点数を表示
    private func showPointsLabel(points: Int, at position: CGPoint) {
        let pointsLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        pointsLabel.text = "+\(points)"
        pointsLabel.fontSize = 40
        pointsLabel.position = position
        pointsLabel.zPosition = 100

        // 点数に応じて色を変える
        if points >= 100 {
            // 高得点（100点以上）: 金色
            pointsLabel.fontColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
        } else if points >= 50 {
            // 中得点（50点以上）: オレンジ
            pointsLabel.fontColor = SKColor.orange
        } else {
            // 低得点（50点未満）: 白
            pointsLabel.fontColor = SKColor.white
        }

        // 影をつける
        let shadow = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        shadow.text = pointsLabel.text
        shadow.fontSize = pointsLabel.fontSize
        shadow.fontColor = SKColor.black
        shadow.alpha = 0.5
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        pointsLabel.addChild(shadow)

        addChild(pointsLabel)

        // アニメーション: 上に移動しながらフェードアウト
        let moveUp = SKAction.moveBy(x: 0, y: 80, duration: 1.0)
        let fadeOut = SKAction.fadeOut(withDuration: 1.0)
        let scaleUp = SKAction.scale(to: 1.3, duration: 0.3)
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.7)

        let scaleSequence = SKAction.sequence([scaleUp, scaleDown])
        let group = SKAction.group([moveUp, fadeOut, scaleSequence])

        pointsLabel.run(group) {
            pointsLabel.removeFromParent()
        }
    }
}
