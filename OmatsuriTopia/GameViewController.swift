import UIKit
import SpriteKit
import SwiftUI
import Combine

class GameViewController: UIViewController {
    private let model = FestivalModel()
    private let gameView = SKView()
    private var overlay: UIHostingController<FestivalOverlay>?
    private var resultOverlay: UIHostingController<FestivalResultOverlay>?
    private var subscription: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        gameView.translatesAutoresizingMaskIntoConstraints = false
        gameView.isMultipleTouchEnabled = true
        view.addSubview(gameView)
        NSLayoutConstraint.activate([
            gameView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameView.topAnchor.constraint(equalTo: view.topAnchor),
            gameView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
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
        subscription = model.$screen.removeDuplicates().sink { [weak self] screen in
            self?.show(screen)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func startGame() {
        view.layoutIfNeeded()
        let scene = GameScene(size: gameView.bounds.size)
        scene.scaleMode = .resizeFill
        scene.onFinish = { [weak self, weak scene] result in
            // Finish the SpriteKit touch/update callback before changing UIKit/SwiftUI views.
            DispatchQueue.main.async {
                guard let self, let scene, self.gameView.scene === scene else { return }
                self.model.finished(result)
            }
        }
        gameView.presentScene(scene)
    }

    private func show(_ screen: FestivalModel.Screen) {
        let showsGame = screen == .playing || screen == .result
        overlay?.view.isHidden = showsGame
        gameView.isHidden = !showsGame
        gameView.isUserInteractionEnabled = screen == .playing

        if screen == .result {
            presentResult()
        } else if !showsGame {
            // Keep the finished scene behind the modal until the player confirms.
            gameView.presentScene(nil)
        }
    }

    private func presentResult() {
        guard resultOverlay == nil else { return }
        let host = UIHostingController(rootView: FestivalResultOverlay(model: model) { [weak self] in
            self?.returnToTitle()
        })
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.isModalInPresentation = true
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true
        resultOverlay = host
        present(host, animated: true)
    }

    private func returnToTitle() {
        guard let resultOverlay else { return }
        model.message = nil
        model.screen = .home
        overlay?.view.layoutIfNeeded()
        // Reveal the title directly, without briefly returning to the finished game.
        resultOverlay.dismiss(animated: false)
        self.resultOverlay = nil
    }

    @objc private func becameActive() {
        Task { await model.retryPending() }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
}
