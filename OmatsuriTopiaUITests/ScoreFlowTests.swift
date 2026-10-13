import XCTest

final class ScoreFlowTests: XCTestCase {
    func testLastShotWaitsForConfirmationBeforeReturningToTitle() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["ひとりで遊ぶ"].waitForExistence(timeout: 10))
        app.buttons["ひとりで遊ぶ"].tap()

        for round in 1...2 {
            var lastShotStarted: TimeInterval = 0
            for shot in 0..<10 {
                let size = app.frame.size
                let fire = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: size.width - 70, dy: size.height - 70))
                if shot == 9 { lastShotStarted = ProcessInfo.processInfo.systemUptime }
                if round == 2 && shot == 9 {
                    fire.press(forDuration: 1)
                } else {
                    fire.tap()
                }
                if shot < 9 {
                    app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: size.width - 190, dy: size.height - 70)).tap()
                    Thread.sleep(forTimeInterval: 0.55)
                }
            }
            // Do not tap reload after the final shot: the result must appear on its own.
            XCTAssertTrue(app.staticTexts["resultScore"].waitForExistence(timeout: 3))
            // Include XCTest's idle wait, which can otherwise hide a long UI stall.
            let transitionTime = ProcessInfo.processInfo.systemUptime - lastShotStarted
            XCTAssertLessThan(transitionTime, 8, "The last shot must not stall the result transition.")
            XCTAssertTrue(app.staticTexts["結果発表"].exists)
            XCTAssertEqual(app.staticTexts["resultEndReason"].label, "10発すべて撃ち終えました")
            attach(app, name: "LastShot-Round\(round)")
            XCTAssertTrue(app.staticTexts["自己ベストをこの端末に保存しました"].exists)
            assertResultWaitsForConfirmation(app)
            app.buttons["resultConfirm"].tap()
            XCTAssertTrue(app.buttons["ひとりで遊ぶ"].waitForExistence(timeout: 3))
            if round == 1 {
                app.buttons["ひとりで遊ぶ"].tap()
                XCTAssertTrue(app.staticTexts["resultScore"].waitForNonExistence(timeout: 3))
            }
        }
    }

    func testTimeLimitWaitsForConfirmationBeforeReturningToTitle() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["ひとりで遊ぶ"].waitForExistence(timeout: 10))
        app.buttons["ひとりで遊ぶ"].tap()
        XCTAssertTrue(app.staticTexts["resultScore"].waitForExistence(timeout: 65))
        XCTAssertEqual(app.staticTexts["resultEndReason"].label, "時間切れ")
        XCTAssertEqual(app.staticTexts["resultScore"].label, "0")
        XCTAssertTrue(app.staticTexts["プレイ時間 60.00秒"].exists)
        XCTAssertTrue(app.staticTexts["命中 0/0"].exists)
        XCTAssertTrue(app.staticTexts["命中率 0%"].exists)
        attach(app, name: "TimeLimit")
        assertResultWaitsForConfirmation(app)
        app.buttons["resultConfirm"].tap()
        XCTAssertTrue(app.buttons["ひとりで遊ぶ"].waitForExistence(timeout: 3))
        app.buttons["ひとりで遊ぶ"].tap()
        XCTAssertTrue(app.staticTexts["resultScore"].waitForNonExistence(timeout: 3))
    }

    func testOfflineRoundAndPersistedBest() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["ひとりで遊ぶ"].waitForExistence(timeout: 10))
        attach(app, name: "Home")
        app.buttons["ひとりで遊ぶ"].tap()
        // Existing SpriteKit controls: fire in the lower right, reload just to its left.
        for shot in 0..<10 {
            let size = app.frame.size
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: size.width - 70, dy: size.height - 70)).tap()
            if shot < 9 {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: size.width - 190, dy: size.height - 70)).tap()
                Thread.sleep(forTimeInterval: 0.55)
            }
        }
        XCTAssertTrue(app.staticTexts["resultScore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["自己ベストをこの端末に保存しました"].exists)
        attach(app, name: "Result")
        let best = app.staticTexts["personalBest"].label
        app.terminate()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.staticTexts["personalBest"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["personalBest"].label, best)
        XCTAssertFalse(app.buttons["参加をやめて記録を削除"].exists)
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        attach(app, name: "Settings")
        app.buttons["プライバシーポリシー"].tap()
        XCTAssertTrue(app.navigationBars["プライバシーポリシー"].waitForExistence(timeout: 5))
    }

    func testOnlineRoundRankingAndDeletion() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OMATSURI_ONLINE_QA"] == "1",
                          "Opt-in live API test. Run only on a disposable simulator.")
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["全国に挑戦"].waitForExistence(timeout: 10))
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        try XCTSkipIf(app.buttons["参加をやめて記録を削除"].exists, "Preserve any existing player.")
        app.buttons["閉じる"].tap()
        app.buttons["全国に挑戦"].tap()
        XCTAssertTrue(app.buttons["内容を確認して参加する"].waitForExistence(timeout: 5))
        app.buttons["内容を確認して参加する"].tap()
        XCTAssertTrue(app.staticTexts["rankingPlayerName"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["参加をやめて記録を削除"].exists)
        app.buttons["全国に挑戦"].tap()
        XCTAssertTrue(app.buttons["全国に挑戦"].waitForNonExistence(timeout: 20))
        for shot in 0..<10 {
            let size = app.frame.size
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: size.width - 70, dy: size.height - 70)).tap()
            if shot < 9 {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: size.width - 190, dy: size.height - 70)).tap()
                Thread.sleep(forTimeInterval: 0.55)
            }
        }
        XCTAssertTrue(app.staticTexts["通算ランキングに登録しました"].waitForExistence(timeout: 20))
        app.buttons["resultConfirm"].tap()
        XCTAssertTrue(app.buttons["通算ランキング"].waitForExistence(timeout: 3))
        app.buttons["通算ランキング"].tap()
        XCTAssertTrue(app.staticTexts["あなたの順位"].waitForExistence(timeout: 20))
        attach(app, name: "AllTimeRanking")
        app.buttons["戻る"].tap()
        let best = app.staticTexts["personalBest"].label
        app.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["参加をやめて記録を削除"].waitForExistence(timeout: 5))
        attach(app, name: "RankingSettings")
        app.buttons["参加をやめて記録を削除"].tap()
        XCTAssertTrue(app.buttons["オンライン記録を削除"].waitForExistence(timeout: 5))
        app.buttons["キャンセル"].tap()
        XCTAssertTrue(app.buttons["参加をやめて記録を削除"].exists)
        app.buttons["参加をやめて記録を削除"].tap()
        app.buttons["オンライン記録を削除"].tap()
        XCTAssertTrue(app.staticTexts["オンライン記録を削除しました。端末の自己ベストは残っています。"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["参加をやめて記録を削除"].exists)
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["全国に挑戦"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["personalBest"].label, best)
    }

    private func assertResultWaitsForConfirmation(_ app: XCUIApplication) {
        let score = app.staticTexts["resultScore"].label
        XCTAssertTrue(app.buttons["resultConfirm"].isHittable)
        XCTAssertFalse(app.buttons["ひとりで遊ぶ"].exists)
        XCTAssertFalse(app.buttons["全国に挑戦"].exists)
        // Tapping outside the card must not dismiss the result or start another game.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.1)).tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.staticTexts["resultScore"].label, score)
        XCTAssertTrue(app.buttons["resultConfirm"].isHittable)
        XCTAssertFalse(app.buttons["ひとりで遊ぶ"].exists)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
