import UIKit
import SpriteKit
import SwiftUI
import Combine

class GameViewController: UIViewController {
    private let model = FestivalModel()
    private var overlay: UIHostingController<FestivalOverlay>?
    private var subscription: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let gameView = view as? SKView else { return }
        gameView.ignoresSiblingOrder = true
        gameView.showsFPS = false
        gameView.showsNodeCount = false
        gameView.backgroundColor = .black
        model.play = { [weak self] in self?.startGame() }
        let host = UIHostingController(rootView: FestivalOverlay(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        overlay = host
        subscription = model.$screen.sink { [weak self] screen in
            self?.overlay?.view.isHidden = screen == .playing
        }
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func startGame() {
        guard let gameView = view as? SKView else { return }
        let scene = GameScene(size: gameView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.onFinish = { [weak self] result in self?.model.finished(result) }
        gameView.presentScene(scene)
    }

    @objc private func becameActive() {
        Task { await model.retryPending() }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
}
