import XCTest
import SwiftData
import UIKit
@testable import KyouNaniTaberu

@MainActor
final class ReceiptTests: XCTestCase {
    func testPorkThighReceiptNamesKeepTheCutAndDoNotInventWeightFromPrice() throws {
        let store = try store(), foods = try ingredients(store)
        let thigh = try XCTUnwrap(masters(store).first { $0.key == "pork_thigh" })
        for name in ["豚もも切り落とし", "豚モモ切落し", "国産豚モモ切落", "ﾌﾞﾀﾓﾓ切落し", "豚腿肉", "豚もも薄切り"] {
            let row = try XCTUnwrap(ReceiptParser.parse([name + " 200g ¥398"], ingredients: foods).first)
            XCTAssertEqual(row.masterID, thigh.id, name)
            XCTAssertEqual(row.name, "豚もも肉"); XCTAssertTrue(row.included)
            XCTAssertEqual(Double(row.quantity), 200); XCTAssertEqual(row.unit, .gram)
            XCTAssertFalse(row.confirmed)
        }
        let unmeasured = try XCTUnwrap(ReceiptParser.parse(["豚もも切り落とし ¥398"], ingredients: foods).first)
        XCTAssertEqual(unmeasured.masterID, thigh.id); XCTAssertTrue(unmeasured.included)
        XCTAssertFalse(unmeasured.exact); XCTAssertTrue(unmeasured.quantity.isEmpty)
        let names = ["鶏もも肉", "豚こま切れ肉", "豚バラ肉", "豚ロース肉", "豚ひき肉"]
        let distinct = try ReceiptParser.parse(names.map { $0 + " 200g ¥398" }, ingredients: foods)
        XCTAssertEqual(distinct.count, names.count)
        XCTAssertTrue(distinct.allSatisfy { $0.masterID != thigh.id && $0.masterID != nil })
    }
    func testPorkThighReceiptImportsSeparatelyFromPorkSlicesAndKeepsSessionIdempotent() throws {
        let store = try store()
        let thigh = try XCTUnwrap(masters(store).first { $0.key == "pork_thigh" })
        let slices = try XCTUnwrap(masters(store).first { $0.key == "pork_slices" })
        let existing = try InventoryService(container: store).save(InventoryDraft(masterID: slices.id, amount: .exact(100, .gram)))
        var rows = try ReceiptParser.parse(["豚もも切り落とし 250g ¥498"], ingredients: ingredients(store))
        rows[0].confirmed = true; rows[0].merge = true
        let service = ReceiptImportService(container: store), session = UUID()
        try service.save(rows: rows, sessionID: session)
        XCTAssertThrowsError(try service.save(rows: rows, sessionID: session))
        let lots = try ModelContext(store).fetch(FetchDescriptor<InventoryItem>())
        XCTAssertEqual(lots.count, 2)
        XCTAssertEqual(lots.first { $0.id == existing }?.quantity, 100)
        XCTAssertEqual(lots.first { $0.ingredientMasterID == thigh.id }?.quantity, 250)
    }
    private func store() throws -> ModelContainer {
        let store = try AppPersistence.makeContainer(inMemory: true)
        try IngredientMasterImporter.load(into: store)
        return store
    }
    private func masters(_ store: ModelContainer) throws -> [IngredientMaster] { try ModelContext(store).fetch(FetchDescriptor<IngredientMaster>()) }
    private func ingredients(_ store: ModelContainer) throws -> [ReceiptIngredient] {
        try masters(store).filter { $0.trackInventory && $0.status == .active }.map {
            ReceiptIngredient(id: $0.id, name: $0.canonicalName, aliases: $0.aliases, unit: $0.defaultUnit,
                allowedUnits: $0.allowedUnits, storage: $0.defaultStorage)
        }
    }
    func testReceiptPricesUnknownItemsAndAmbiguousCountsAreNotInvented() throws {
        let store = try store()
        let rows = try ReceiptParser.parse(["牛乳 １０００ｍｌ ¥198", "牛乳 1本 ¥198", "卵 ¥298", "台所スポンジ ¥100", "牛乳 1000ml ×2点 ¥396", "合計 ¥1280"], ingredients: ingredients(store))
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows[0].exact); XCTAssertEqual(Double(rows[0].quantity), 1000)
        XCTAssertEqual(rows[0].unit, .milliliter)
        XCTAssertFalse(rows[1].exact); XCTAssertFalse(rows[2].exact); XCTAssertFalse(rows[4].exact)
        XCTAssertFalse(rows[3].included); XCTAssertNil(rows[3].masterID)
        XCTAssertTrue(rows.allSatisfy { !$0.confirmed && $0.expiresAt == nil })
        XCTAssertFalse(rows[3].name.contains("100"))
        XCTAssertThrowsError(try ReceiptParser.parse(Array(repeating: "牛乳", count: 121), ingredients: ingredients(store)))
    }
    func testPackMultipliersRefundsAndSingleCharacterFoodNamesNeedCare() throws {
        let store = try store()
        let rows = try ReceiptParser.parse(["牛乳 1000ml x2", "牛乳 1000ml 2本", "牛乳 -198円", "塩 ¥100"], ingredients: ingredients(store))
        XCTAssertEqual(rows.count, 4)
        XCTAssertFalse(rows[0].exact); XCTAssertFalse(rows[1].exact)
        XCTAssertFalse(rows[2].included)
        XCTAssertEqual(rows[3].name, "塩"); XCTAssertTrue(rows[3].included)
    }
    func testShoppingBagChargesAreDiscardedButFoodBagsAndUnknownProductsRemain() throws {
        let bags = ["レジ袋 ¥3", "レジ袋(大) 5円", "有料袋 ¥5", "袋代 3円", "ビニール袋 ¥5", "ポリ袋 1枚 ¥3", "ショッピングバッグ ¥10", "レジバック ¥5", "ﾚｼﾞﾌﾞｸﾛ ¥5", "レシフクロ ¥5", "買物袋 ¥3", "お買い物袋 ¥5", "手さげ袋 ¥10", "エコバッグ ¥300", "袋料金 ¥5"]
        let food = try ingredients(store())
        XCTAssertTrue(try ReceiptParser.parse(bags, ingredients: food).isEmpty)
        let rows = try ReceiptParser.parse(["有料袋", "5", "牛乳 1000ml ¥198", "もやし 1袋 ¥30", "油揚げ 1袋 ¥100", "袋麺 ¥100", "台所スポンジ ¥100"], ingredients: food)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].name, "牛乳")
        XCTAssertTrue(rows.contains { $0.source.contains("油揚げ") })
        XCTAssertTrue(rows.contains { $0.source == "袋麺 ¥100" })
        XCTAssertTrue(rows.contains { $0.source == "台所スポンジ ¥100" && !$0.included })
    }
    func testMultipleIngredientMatchesRequireExplicitChoice() throws {
        let a = ReceiptIngredient(id: UUID(), name: "牛乳", aliases: [], unit: .milliliter, allowedUnits: [.milliliter], storage: .refrigerated)
        let b = ReceiptIngredient(id: UUID(), name: "低脂肪牛乳", aliases: [], unit: .milliliter, allowedUnits: [.milliliter], storage: .refrigerated)
        let row = try XCTUnwrap(ReceiptParser.parse(["低脂肪牛乳 1000ml"], ingredients: [a,b]).first)
        XCTAssertNil(row.masterID); XCTAssertFalse(row.included)
    }
    func testReceiptHeaderAddressTaxAndPaymentDoNotBecomeProducts() throws {
        let foods = try ingredients(store())
        let rows = try ReceiptParser.parse([
            "スーパー牛乳 町田店", "レモン青果", "株式会社たまご", "東京都新宿区ねぎ町1丁目2番3号",
            "〒160-0000", "ｔｅｌ：０３－１２３４－５６７８", "2026年10月10日(土) 17:30",
            "レジ03 担当 豆腐", "領収証", "T1234567890123", "本日おすすめ 牛乳 ¥198",
            "会員様限定 たまご", "いつもありがとうございます", "牛乳 1000ml ¥198", "卵 6個 ¥298",
            "小計 ¥496", "8%対象 ¥496", "(内消費税 ¥36)", "合計 ¥496", "お預り ¥1000",
            "お釣り ¥504", "保有ポイント 100", "レモン ¥98", "ご来店ありがとうございます"
        ], ingredients: foods)
        XCTAssertEqual(rows.map(\.name), ["牛乳", "卵"])
        XCTAssertTrue(rows.allSatisfy { $0.included && !$0.confirmed })
        XCTAssertEqual(Double(rows[0].quantity), 1000)
        XCTAssertEqual(Double(rows[1].quantity), 6)
    }
    func testSplitPricesAndUnpricedFoodsSurviveButUnknownProseDoesNot() throws {
        let foods = try ingredients(store())
        let rows = try ReceiptParser.parse([
            "ようこそ", "本日の担当者", "牛乳 1000ml", "￥198", "極小粒ミニ3", "98円※",
            "卵", "さまざまな商品を取りそろえております", "台所スポンジ 100", "4901234567890", "塩 @100"
        ], ingredients: foods)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].name, "牛乳"); XCTAssertEqual(Double(rows[0].quantity), 1000)
        XCTAssertEqual(rows[1].source, "極小粒ミニ3"); XCTAssertNil(rows[1].masterID)
        XCTAssertFalse(rows[1].exact); XCTAssertFalse(rows[1].included)
        XCTAssertEqual(rows[2].name, "卵"); XCTAssertFalse(rows[2].exact)
        XCTAssertEqual(rows[3].source, "台所スポンジ 100"); XCTAssertFalse(rows[3].included)
        XCTAssertEqual(rows[4].name, "塩")
    }
    func testDiscountsAndTaxNotesDoNotEndProductList() throws {
        let rows = try ReceiptParser.parse([
            "お買上", "お買上げ", "牛乳 198円", "値引 牛乳 -20円", "8.0%対象商品", "※は軽減税率対象",
            "卵 298円", "割引対象 レモン 98円", "クーポン割引 -10円", "塩 100円"
        ], ingredients: ingredients(store()))
        XCTAssertEqual(rows.map(\.name), ["牛乳", "卵", "塩"])
        XCTAssertTrue(rows.allSatisfy { $0.included && !$0.exact })
    }
    func testSubtotalEndsProductsIncludingSplitAmountsAndPaymentFoodNames() throws {
        let foods = try ingredients(store())
        for boundary in ["小計", "小 計", "小計 178円", "小計(税込)￥178", "小計（税抜）", "小計金額", "小計(8%)", "支払い", "お支払", "支払金額 ￥178", "PayPay", "PayPay ￥178"] {
            let rows = try ReceiptParser.parse(["牛乳 198円", boundary, "178", "卵 298円", "支払い レモン", "塩 100円"], ingredients: foods)
            XCTAssertEqual(rows.map(\.name), ["牛乳"], boundary)
        }
        let rows = try ReceiptParser.parse(["小計印のお菓子 100円", "卵 298円"], ingredients: foods)
        XCTAssertTrue(rows.contains { $0.name == "卵" })
    }
    func testPricedFooterProductsAreExcludedAfterTotalOrPayment() throws {
        let foods = try ingredients(store())
        for total in ["合計（税込）￥198", "お会計 198円", "お支払い金額 ￥198", "お預り 1000円", "お釣り 802円", "現金 198円", "クレジット売上 ￥198", "お買上げ合計 198円", "VISA 198円", "合計"] {
            let rows = try ReceiptParser.parse(["牛乳 1000ml ¥198", total, "卵 6個 ¥98", "チーズ 100円", "限定商品 50円"], ingredients: foods)
            XCTAssertEqual(rows.map(\.name), ["牛乳"], total)
        }
    }
    func testProductNamesContainingFoodAliasesRequireChoice() throws {
        let lemon = ReceiptIngredient(id: UUID(), name: "レモン", aliases: [], unit: .piece,
            allowedUnits: [.piece], storage: .refrigerated)
        let rows = try ReceiptParser.parse([
            "ＣＣレモンマスカット ¥128", "C.C.レモン 500ml 128円", "レモンソーダ 128円", "レモン洗剤 ¥198",
            "国産レモン 2個 198円", "レモン"
        ], ingredients: [lemon])
        XCTAssertEqual(rows.count, 6)
        for row in rows.prefix(4) {
            XCTAssertNil(row.masterID); XCTAssertFalse(row.included); XCTAssertFalse(row.exact)
            XCTAssertFalse(row.confirmed); XCTAssertFalse(row.source.isEmpty)
        }
        XCTAssertEqual(rows[4].masterID, lemon.id); XCTAssertEqual(Double(rows[4].quantity), 2)
        XCTAssertEqual(rows[5].masterID, lemon.id)
    }
    func testMetadataOnlyReceiptHasNoProductCandidates() throws {
        let rows = try ReceiptParser.parse(["いらっしゃいませ", "レモンマーケット", "TEL 03-1234-5678",
            "2026/10/10 17:30", "合計 ¥0", "毎度ありがとうございます"], ingredients: ingredients(store()))
        XCTAssertTrue(rows.isEmpty)
    }
    func testMissingDakutenOffersBroccoliWithoutSelectingOrLosingUnpricedFood() throws {
        let food = ReceiptIngredient(id: UUID(), name: "ブロッコリー", aliases: ["ぶろっこりー"],
            unit: .gram, allowedUnits: [.gram, .piece], storage: .refrigerated)
        let rows = try ReceiptParser.parse(["フロッコリー 200g ¥158", "ﾌﾛｯｺﾘｰ", "フロッコリーストア"], ingredients: [food])
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertNil(row.masterID); XCTAssertFalse(row.included); XCTAssertFalse(row.confirmed)
            XCTAssertEqual(row.suggestedMasterIDs, [food.id])
        }
        XCTAssertTrue(ReceiptParser.searchMatches("ふろっこりー", names: [food.name]))
        XCTAssertTrue(ReceiptParser.searchMatches("ﾌﾞﾛｯｺﾘｰ", names: [food.name]))
        XCTAssertFalse(ReceiptParser.searchMatches("カリフラワー", names: [food.name]))
    }
    func testVoicingCollisionsAndDrinkNamesCannotBecomeAutomaticMatches() throws {
        let a = ReceiptIngredient(id: UUID(), name: "はなまめ", aliases: [], unit: .piece, allowedUnits: [.piece], storage: .refrigerated)
        let b = ReceiptIngredient(id: UUID(), name: "ばなまめ", aliases: [], unit: .piece, allowedUnits: [.piece], storage: .refrigerated)
        let rows = try ReceiptParser.parse(["ぱなまめ 100円", "ぱなまめソーダ 100円"], ingredients: [a,b])
        XCTAssertEqual(Set(rows[0].suggestedMasterIDs), Set([a.id,b.id]))
        XCTAssertTrue(rows[1].suggestedMasterIDs.isEmpty)
        XCTAssertTrue(rows.allSatisfy { $0.masterID == nil && !$0.included })
    }
    func testExplicitSelectionRestoresQuantityAndKeepsEditedStorageAndDates() throws {
        let food = ReceiptIngredient(id: UUID(), name: "ブロッコリー", aliases: [], unit: .gram,
            allowedUnits: [.gram, .piece], storage: .refrigerated)
        var row = try XCTUnwrap(ReceiptParser.parse(["フロッコリー 200g ¥158"], ingredients: [food]).first)
        row.storage = .frozen; row.storageOverridden = true; row.purchaseDateOverridden = true
        row.purchasedAt = Date(timeIntervalSince1970: 1_700_000_000)
        row.expiresAt = row.purchasedAt.addingTimeInterval(86400); row.expiryKind = .useBy
        let selected = ReceiptParser.resolving(row, as: food)
        XCTAssertEqual(selected.id, row.id); XCTAssertEqual(selected.source, row.source)
        XCTAssertEqual(selected.masterID, food.id); XCTAssertEqual(selected.name, "ブロッコリー")
        XCTAssertEqual(Double(selected.quantity), 200); XCTAssertEqual(selected.unit, .gram)
        XCTAssertTrue(selected.included); XCTAssertFalse(selected.confirmed); XCTAssertTrue(selected.suggestedMasterIDs.isEmpty)
        XCTAssertEqual(selected.storage, .frozen); XCTAssertEqual(selected.purchasedAt, row.purchasedAt)
        XCTAssertEqual(selected.expiresAt, row.expiresAt); XCTAssertEqual(selected.expiryKind, .useBy)
        XCTAssertTrue(selected.storageOverridden); XCTAssertTrue(selected.purchaseDateOverridden)
        row.exact = true; row.quantity = "2"; row.unit = .piece
        XCTAssertEqual(ReceiptParser.resolving(row, as: food).quantity, "2")
    }
    func testConfirmationAtomicRollbackAndSameSessionCannotSaveTwice() throws {
        let store = try store()
        var rows = try ReceiptParser.parse(["牛乳 1000ml ¥198", "台所スポンジ ¥100"], ingredients: ingredients(store))
        let service = ReceiptImportService(container: store), session = UUID()
        XCTAssertThrowsError(try service.save(rows: rows, sessionID: session))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 0)
        rows[0].confirmed = true
        var invalid = ReceiptRow(name: "調味料"); invalid.confirmed = true; invalid.exact = true; invalid.quantity = "-1"
        XCTAssertThrowsError(try service.save(rows: rows + [invalid], sessionID: session))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 0)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<CustomIngredient>()), 0)
        try service.save(rows: rows, sessionID: session)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 1)
        XCTAssertThrowsError(try service.save(rows: rows, sessionID: session))
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 1)
        let events = try ModelContext(store).fetch(FetchDescriptor<InventoryEvent>())
        XCTAssertFalse(events.contains { $0.note.contains("¥198") || $0.note.contains("牛乳") })
    }
    func testCustomIngredientAndExplicitMergeKeepDifferentLotsSeparate() throws {
        let store = try store()
        let milk = try XCTUnwrap(masters(store).first { $0.key == "milk" })
        let id = try InventoryService(container: store).save(InventoryDraft(masterID: milk.id, amount: .exact(500, .milliliter)))
        var row = ReceiptRow(masterID: milk.id, name: milk.canonicalName)
        row.confirmed = true; row.exact = true; row.quantity = "1"; row.unit = .liter; row.merge = true
        try ReceiptImportService(container: store).save(rows: [row], sessionID: UUID())
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<InventoryItem>()).first { $0.id == id }?.quantity, 1500)
        row.expiresAt = .now.addingTimeInterval(86400 * 4)
        try ReceiptImportService(container: store).save(rows: [row], sessionID: UUID())
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 2)
        var custom = ReceiptRow(name: "手作りソース"); custom.confirmed = true; custom.category = .seasoning
        try ReceiptImportService(container: store).save(rows: [custom], sessionID: UUID())
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<CustomIngredient>()), 1)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<CustomIngredient>()).first?.category, .seasoning)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 3)
    }
    func testVisionReadsGeneratedReceiptInMemory() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 900))
        let data = renderer.pngData { canvas in
            UIColor.white.setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 1400, height: 900))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 60), .foregroundColor: UIColor.black]
            "牛乳 1000ml  198円".draw(at: CGPoint(x: 100, y: 150), withAttributes: attributes)
            "卵 6個  298円".draw(at: CGPoint(x: 100, y: 300), withAttributes: attributes)
            "合計 496円".draw(at: CGPoint(x: 100, y: 450), withAttributes: attributes)
        }
        let lines = try await ReceiptOCR.recognize(data: data)
        XCTAssertTrue(lines.joined().contains("牛乳"), lines.joined(separator: "\n"))
        let rows = try ReceiptParser.parse(lines, ingredients: ingredients(store()))
        XCTAssertTrue(rows.contains { $0.name == "牛乳" && $0.included && !$0.confirmed })
    }
    func testVisionReceiptWithHeaderAndPricedFooterKeepsOnlyPurchasedFood() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 1600), format: format).pngData { canvas in
            UIColor.white.setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 1400, height: 1600))
            let lines = ["スーパー牛乳 町田店", "TEL 03-1234-5678", "東京都新宿区ねぎ町1丁目2番3号",
                "2026年10月10日 17:30", "牛乳 1000ml 198円", "小計 198円", "合計 198円",
                "卵 6個 98円", "ご来店ありがとうございます"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 80, y: 100 + index * 150), withAttributes: [.font: UIFont.systemFont(ofSize: 54), .foregroundColor: UIColor.black])
            }
        }
        let lines = try await ReceiptOCR.recognize(data: data)
        let rows = try ReceiptParser.parse(lines, ingredients: ingredients(store()))
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.name, "牛乳"); XCTAssertEqual(Double(row.quantity), 1000)
        XCTAssertTrue(row.included); XCTAssertFalse(row.confirmed)
    }
    func testUnreadableImageFailsWithoutCreatingInventory() async throws {
        do { _ = try await ReceiptOCR.recognize(data: Data([0, 1, 2])); XCTFail("Expected invalid image") }
        catch { XCTAssertTrue(error is ReceiptError) }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500))
        let data = renderer.pngData { canvas in UIColor.white.setFill(); canvas.fill(CGRect(x: 0, y: 0, width: 500, height: 500)) }
        do { _ = try await ReceiptOCR.recognize(data: data); XCTFail("Expected no text") }
        catch { XCTAssertTrue(error is ReceiptError) }
    }
    func testExpandedFoodsRecognizeReadingsButKeepFreshAndCannedFishAmbiguous() throws {
        let store = try store()
        let foods = try ingredients(store)
        let rows = try ReceiptParser.parse(["鶏むね肉 200g 198円", "えのき 1パック 100円", "サバの切り身 2個 300円"], ingredients: foods)
        XCTAssertEqual(rows[0].name, "鶏むね肉"); XCTAssertEqual(Double(rows[0].quantity), 200)
        XCTAssertEqual(rows[1].name, "えのき"); XCTAssertEqual(rows[1].unit, .pack)
        XCTAssertNil(rows[2].masterID); XCTAssertFalse(rows[2].included)
        XCTAssertTrue(rows.allSatisfy { !$0.confirmed })
        let voice = try VoiceParser.parse("とりむねにくを二百グラム買った", ingredients: foods)
        XCTAssertEqual(voice.first?.draft.name, "鶏むね肉")
        XCTAssertEqual(Double(voice.first?.draft.quantity ?? ""), 200)
        XCTAssertEqual(voice.first?.action, .add); XCTAssertFalse(voice.first!.draft.confirmed)
    }

    func testDriedFoodsRecognizeReadingsAndAmbiguousNamesNeedSelection() throws {
        let store = try store(), foods = try ingredients(store)
        let rows = try ReceiptParser.parse(["マカロニ 200g 198円", "干ししいたけ 30g 298円", "コーン缶 1缶 100円"], ingredients: foods)
        XCTAssertEqual(rows[0].name, "マカロニ"); XCTAssertEqual(Double(rows[0].quantity), 200)
        XCTAssertNil(rows[1].masterID); XCTAssertFalse(rows[1].included)
        XCTAssertNil(rows[2].masterID); XCTAssertFalse(rows[2].included)
        let voice = try VoiceParser.parse("まかろにを五十グラム買った", ingredients: foods)
        XCTAssertEqual(voice.first?.draft.name, "マカロニ")
        XCTAssertEqual(Double(voice.first?.draft.quantity ?? ""), 50)
        XCTAssertEqual(voice.first?.action, .add); XCTAssertFalse(voice.first!.draft.confirmed)
        let meat = try VoiceParser.parse("鶏もも肉を200g買った", ingredients: foods)
        XCTAssertEqual(meat.first?.draft.name, "鶏もも肉")
        XCTAssertEqual(Double(meat.first?.draft.quantity ?? ""), 200)
        XCTAssertFalse(meat.first!.draft.confirmed)
        XCTAssertEqual(try ModelContext(store).fetchCount(FetchDescriptor<InventoryItem>()), 0)
    }

}
