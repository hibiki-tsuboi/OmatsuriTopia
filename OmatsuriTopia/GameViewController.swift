//
//  GameViewController.swift
//  OmatsuriTopia
//
//  Created by Hibiki Tsuboi on 2025/12/21.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        if let view = self.view as! SKView? {
            // ビューのサイズに合わせてシーンを作成
            let scene = GameScene(size: view.bounds.size)
            scene.scaleMode = .resizeFill  // ビューに完全にフィットさせる

            // シーンを表示
            view.presentScene(scene)

            view.ignoresSiblingOrder = true

            view.showsFPS = true
            view.showsNodeCount = true
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
