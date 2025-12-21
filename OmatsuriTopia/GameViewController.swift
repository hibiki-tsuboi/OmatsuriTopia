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
            // プログラムでシーンを作成（横向きiPad用のサイズ）
            let scene = GameScene(size: CGSize(width: 1334, height: 750))
            scene.scaleMode = .aspectFill

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
