import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var expiryNotifications: ExpiryNotifications
    let recipes: [Recipe]
    var openPlan: (() -> Void)? = nil
    @State private var showMyPage = false
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @State private var evaluationDate = Date.now
    @State private var suggestionCache = HomeSuggestionCache()
    @Query(sort: \MealSelection.date, order: .reverse) private var meals: [MealSelection]
    @State private var showRecipeList = false
    @State private var showNotices = false
    @AppStorage(AppPreferences.readNoticeIDs) private var readNoticeJSON = ""
    private var unreadNoticeCount: Int {
        let items = AppNoticeFeed.expiry(AppNoticeFeed.stock(stock, masters: masters, customs: customs), days: expiryNotifications.days, now: evaluationDate) + AppNoticeFeed.updates()
        let read = NoticeReadState.ids(readNoticeJSON)
        return items.filter { !read.contains($0.id) }.count
    }
    @State private var browseIngredientKey: String?
    @State private var browseKind: RecipeKind = .all
    @State private var showIngredientPicker = false
    @State private var requiredIngredientKey: String?
    @State private var recipeKind: RecipeKind = .main
    @State private var candidateLimit = 8
    @AppStorage(AppPreferences.defaultServings) private var preferredServings = 1
    @State private var showAdd = false
    @State private var mealDetailID: UUID?
    @State private var expiryItem: InventoryItem?
    @State private var mealError: String?
    @State private var recommendationAddition: (recipeID: UUID, shoppingCount: Int)?
    @State private var addRecommendationShortages = true
    private func candidates(stock snapshots: [StockLot]) -> [RecipeSuggestion] {
        suggestionCache.candidates(recipes.filter { recipeKind.includes($0) },
            foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }, stock: snapshots,
            requiredIngredientKey: requiredIngredientKey, servings: AppPreferences.validatedServings(preferredServings),
            on: evaluationDate)
    }
    private func expiryItems(_ ids: [UUID]) -> [InventoryItem] {
        let byID = Dictionary(uniqueKeysWithValues: stock.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
    private func foodName(_ item: InventoryItem) -> String {
        masters.first { $0.id == item.ingredientMasterID }?.canonicalName
            ?? customs.first { $0.id == item.customIngredientID }?.name ?? "食材"
    }
    private func expiryRow(_ item: InventoryItem) -> some View {
        Button { expiryItem = item } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout())
            HStack(spacing: 8) {
                layout {
                    Text(foodName(item))
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text(expiryLabel(item)).font(AppFont.caption).foregroundStyle(AppTheme.warning)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondary.opacity(0.45)).accessibilityHidden(true)
            }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityElement(children: .combine)
            .accessibilityIdentifier("home-expiry-" + item.id.uuidString)
    }
    var body: some View {
        let snapshots = IngredientIdentity.snapshots(stock, customs: customs, masters: masters)
        let suggestions = candidates(stock: snapshots)
        let near = expiryItems(StockExpiry.near(snapshots, on: evaluationDate))
        let unreadCount = unreadNoticeCount
        NavigationStack {
            List {
                let todayMeals = meals.filter { $0.isActive && $0.plannedDay(on: evaluationDate) == MealPlanning.day(evaluationDate) }
                if !todayMeals.isEmpty {
                    Section {
                        Button { openPlan?() } label: {
                            HStack {
                                Label("今日の献立", systemImage: "calendar")
                                Spacer()
                                Text("\(todayMeals.count)品").foregroundStyle(AppTheme.secondary)
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("home-meal-plan")
                    }
                }
                homeEntrySection
                Section {
                    if let first = suggestions.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Button { mealDetailID = first.recipe.id } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    RecipePhoto(suggestion: first, height: typeSize.isAccessibilitySize ? 340 : 170, identifier: "home-hero")
                                    Text(first.recipe.title).font(AppFont.title2.bold()).foregroundStyle(AppTheme.text)
                                    SuggestionSummaryView(suggestion: first, identifier: "home-hero")
                                }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
                            }.buttonStyle(.plain).accessibilityHint("レシピ詳細を開きます")
                                .accessibilityIdentifier("home-recipe-hero")
                            recommendationAction(first).padding(.bottom, 12)
                        }.padding(.horizontal, 12)
                            .background { AppCardSurface(cornerRadius: 24, shadow: .recommendation) }
                            .padding(EdgeInsets(top: 8, leading: 10, bottom: 14, trailing: 10))
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    if suggestions.isEmpty {
                        Text("条件に合う料理がありません。")
                            .accessibilityIdentifier("home-ingredient-empty")
                    }
                    if stock.filter({ !$0.isDeleted }).isEmpty {
                        Text("冷蔵庫にあるものを登録すると、在庫に合う順に料理を選べます。")
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                        Button("食材を登録する") { showAdd = true }
                    }
                } header: { recommendationHeader }
                if !near.isEmpty {
                    Section("期限が近いもの（\(near.count)品）") {
                        VStack(spacing: 0) {
                            ForEach(Array(near.prefix(5).enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().accessibilityHidden(true) }
                                expiryRow(item).buttonStyle(.plain).foregroundStyle(AppTheme.text)
                                    .padding(.vertical, 6)
                            }
                            if near.count > 5 {
                                Divider().accessibilityHidden(true)
                                DisclosureGroup("残り\(near.count - 5)品を見る") {
                                    ForEach(near.dropFirst(5)) { item in
                                        expiryRow(item).buttonStyle(.plain).foregroundStyle(AppTheme.text)
                                            .padding(.vertical, 6)
                                    }
                                }.padding(.vertical, 6)
                            }
                        }.accessibilityElement(children: .contain)
                            .padding(.horizontal, 16).padding(.vertical, 4)
                            .background { AppCardSurface(cornerRadius: 24, shadow: .expiry) }
                            .padding(8)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    ForEach(suggestions.dropFirst().prefix(candidateLimit)) { suggestion in
                        Button { mealDetailID = suggestion.recipe.id } label: {
                            RecipeCandidateRow(suggestion: suggestion, identifier: "home-alternative-" + suggestion.recipe.key)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("レシピ詳細を開きます")
                            .accessibilityIdentifier("home-alternative-" + suggestion.recipe.key)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    if suggestions.count > candidateLimit + 1 {
                        Button("もっと見る") { candidateLimit += 8 }
                            .frame(minHeight: 44).accessibilityIdentifier("home-more-candidates")
                    }
                    NavigationLink(requiredIngredientKey == nil ? "レシピ一覧" : "この食材のレシピ") {
                        RecipeListView(recipes: recipes, requiredIngredientKey: $requiredIngredientKey, recipeKind: $recipeKind)
                    }.accessibilityIdentifier("home-recipes")
                } header: {
                    Text("ほかの候補").font(AppFont.headline).textCase(nil)
                }
                HomeShoppingSummary()
            }
            .contentMargins(.top, 4, for: .scrollContent)
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .modifier(PageHeading(title: "今日何作る？", icon: "fork.knife"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showMyPage = true } label: { Label("マイページ", systemImage: "person.crop.circle") }
                    } label: { FlatToolbarIcon(systemName: "line.3.horizontal") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("メニュー").accessibilityIdentifier("home-menu")
                }.flatToolbarBackground()
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNotices = true } label: {
                        FlatToolbarIcon(systemName: "bell")
                            .overlay(alignment: .topTrailing) {
                                if unreadCount > 0 {
                                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                                        .font(AppFont.caption2.bold()).foregroundStyle(.white).padding(3)
                                        .background(AppTheme.accentFill, in: Capsule()).accessibilityHidden(true)
                                }
                            }
                    }.buttonStyle(.plain).accessibilityLabel("お知らせ").accessibilityValue("未読\(unreadCount)件")
                        .accessibilityIdentifier("home-notifications")
                }.flatToolbarBackground()
            }
            .navigationDestination(isPresented: $showMyPage) { MyPageView(embedded: true) }
            .sheet(isPresented: $showNotices) { NavigationStack { NoticeInboxView(recipes: recipes) } }
            .navigationDestination(isPresented: $showRecipeList) {
                RecipeListView(recipes: recipes, requiredIngredientKey: $browseIngredientKey, recipeKind: $browseKind)
            }
            .navigationDestination(item: $mealDetailID) { id in
                if let recipe = recipes.first(where: { $0.id == id }) { RecipeDetailView(recipe: recipe) }
            }
            .navigationDestination(item: $expiryItem) { item in InventoryEditorView(item: item) }
            .modifier(RecipeDateRefresh(date: $evaluationDate))
            .onChange(of: recipeKind) { _, _ in candidateLimit = 8 }
            .onChange(of: requiredIngredientKey) { _, _ in candidateLimit = 8 }
            .alert("献立を更新できませんでした", isPresented: Binding(get: { mealError != nil }, set: { if !$0 { mealError = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(mealError ?? "") }
            .sheet(isPresented: $showIngredientPicker) { RecipeIngredientPicker(selection: $requiredIngredientKey) }
            .sheet(isPresented: $showAdd) { InventoryEditorView() }

        }
    }
    private var selectedIngredient: IngredientMaster? { masters.first { $0.key == requiredIngredientKey } }
    private var homeEntrySection: some View {
        Section {
            VStack(alignment: .trailing, spacing: 4) {
                if typeSize.isAccessibilitySize {
                    stackedEntries
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            recipeEntry(compact: true).frame(minWidth: 167, maxWidth: .infinity)
                            ingredientEntry(compact: true).frame(minWidth: 167, maxWidth: .infinity)
                        }
                        stackedEntries
                    }
                }
                if requiredIngredientKey != nil {
                    Button { requiredIngredientKey = nil } label: {
                        Label("解除", systemImage: "xmark.circle").font(AppFont.caption)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless).accessibilityLabel("食材の絞り込みを解除")
                        .accessibilityIdentifier("recipe-ingredient-clear")
                }
            }.listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                .listRowBackground(Color.clear)
        }
    }
    private var stackedEntries: some View {
        VStack(spacing: 10) { recipeEntry(compact: false); ingredientEntry(compact: false) }
    }
    private func recipeEntry(compact: Bool) -> some View {
        Button {
            browseIngredientKey = nil; browseKind = .all; showRecipeList = true
        } label: { IllustratedRecipeLabel(compact: compact) }
            .buttonStyle(.plain).accessibilityIdentifier("home-recipe-entry")
            .accessibilityHint("料理名と種類でレシピを探します")
    }
    private func ingredientEntry(compact: Bool) -> some View {
        Button { showIngredientPicker = true } label: {
            IllustratedIngredientLabel(title: selectedIngredient?.canonicalName ?? "食材から\n選ぶ", compact: compact)
        }.buttonStyle(.plain).accessibilityIdentifier("recipe-ingredient-picker")
            .accessibilityValue(selectedIngredient?.canonicalName ?? "指定なし")
    }
    private func recommendationAction(_ suggestion: RecipeSuggestion) -> some View {
        let selected = meals.first { $0.isActive && $0.recipeID == suggestion.id && $0.plannedDay(on: evaluationDate) == MealPlanning.day(evaluationDate) }
        let added = selected != nil
        return VStack(alignment: .leading, spacing: 8) {
            if !added { MealShoppingCheckbox(isOn: $addRecommendationShortages, identifier: "home-add-shortages") }
            Button { addRecommendation(suggestion) } label: {
                Label(added ? "献立に追加済み" : "献立に加える", systemImage: added ? "checkmark" : "plus")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }.buttonStyle(CoralPrimaryButtonStyle(fill: AppTheme.mealAddFill)).disabled(added)
                .accessibilityIdentifier("home-recommendation-add")
                .accessibilityValue("\(selected?.servings ?? suggestion.servings)人分")
                .accessibilityHint(added ? "決めた献立から確認できます" : "\(suggestion.servings)人分を献立に追加します")
            if added, let addition = recommendationAddition, addition.recipeID == suggestion.id, addition.shoppingCount > 0 {
                Text("買い物リストに\(addition.shoppingCount)品を追加しました。")
                    .font(AppFont.caption).foregroundStyle(AppTheme.accent).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("home-shopping-completion")
            }
        }
    }
    private func addRecommendation(_ suggestion: RecipeSuggestion) {
        guard !meals.contains(where: { $0.isActive && $0.recipeID == suggestion.id && $0.plannedDay(on: evaluationDate) == MealPlanning.day(evaluationDate) }) else { return }
        do {
            let count = try MealService(container: context.container).select(recipe: suggestion.recipe, servings: suggestion.servings, addShortagesToShopping: addRecommendationShortages)
            recommendationAddition = (suggestion.id, count)
        } catch { mealError = error.localizedDescription }
    }
    private var recommendationHeader: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            HStack(spacing: 7) {
                SimpleChefHat().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 23, height: 23).accessibilityHidden(true)
                Text("今日のおすすめ").font(AppFont.headline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(Color(uiColor: .label))
                .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home-recommendation-heading")
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Menu {
                Picker("料理の種類", selection: $recipeKind) {
                    ForEach(RecipeKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease").accessibilityHidden(true)
                    Text(recipeKind.label).font(AppFont.subheadline.weight(.semibold))
                }.fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .foregroundStyle(AppTheme.accent)
                    .background(AppTheme.accentSoft, in: Capsule())
            }.buttonStyle(.borderless).accessibilityLabel("料理の種類")
                .accessibilityValue(recipeKind.label).accessibilityIdentifier("recipe-kind-filter")
        }.textCase(nil)
    }
}
/// Shopping updates redraw this summary without recalculating all home recommendations.
private struct HomeShoppingSummary: View {
    @Query(filter: #Predicate<ShoppingListItem> { !$0.isAddedToInventory && !$0.isChecked })
    private var open: [ShoppingListItem]
    var body: some View {
        if !open.isEmpty {
            Section("買うもの \(open.count)品") {
                ForEach(open.prefix(3)) { Text($0.name) }
            }
        }
    }
}

struct RecipeListView: View {
    let recipes: [Recipe]
    @Binding var requiredIngredientKey: String?
    @Binding var recipeKind: RecipeKind
    @AppStorage(AppPreferences.defaultServings) private var preferredServings = 1
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @State private var evaluationDate = Date.now
    @State private var search = ""
    private var filtered: [Recipe] {
        recipes.filter { $0.status == "active" && recipeKind.includes($0)
            && RecipeSuggestions.includesRequiredIngredient($0, key: requiredIngredientKey)
            && IngredientSearch.matches(search, names: [$0.title]) }
    }
    var body: some View {
        let matchingRecipes = filtered
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let snapshots = IngredientIdentity.snapshots(stock, customs: customs, masters: masters)
        let servings = AppPreferences.validatedServings(preferredServings)
        List {
            Section {
                LabeledFilterMenu(title: "料理の種類", selection: $recipeKind, options: RecipeKind.allCases, label: { $0.label })
                    .accessibilityIdentifier("recipe-kind-filter")
                if let key = requiredIngredientKey {
                    HStack {
                        Text(masters.first { $0.key == key }?.canonicalName ?? "選択中の食材")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button { requiredIngredientKey = nil } label: {
                            Label("解除", systemImage: "xmark.circle").font(AppFont.caption).frame(minHeight: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("食材の絞り込みを解除")
                            .accessibilityIdentifier("recipe-ingredient-clear")
                    }
                }
            }.listRowBackground(AppTheme.surface)
            if matchingRecipes.isEmpty {
                Text("条件に合う料理がありません。")
                    .accessibilityIdentifier("recipe-filter-empty")
                Button("条件をリセット") { search = ""; recipeKind = .all; requiredIngredientKey = nil }
                    .frame(minHeight: 44).accessibilityIdentifier("recipe-filter-reset")
            }
            ForEach(["main", "side"], id: \.self) { role in
                let rows = matchingRecipes.filter { $0.role == role }
                if !rows.isEmpty { Section(role == "main" ? "主食・主菜" : "汁物・副菜") {
                    ForEach(rows) {
                        recipe in
                        NavigationLink { RecipeDetailView(recipe: recipe) } label: {
                            RecipeCandidateRow(suggestion: RecipeSuggestions.evaluate(recipe,
                                foods: foods, stock: snapshots, servings: servings, on: evaluationDate), identifier: "recipe-list-" + recipe.key)
                        }.accessibilityIdentifier("recipe-\(recipe.key)")
                    }
                } }
            }
        }.scrollContentBackground(.hidden).background(AppTheme.background)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "料理名で検索").navigationTitle("レシピ").navigationBarTitleDisplayMode(.inline)
            .modifier(RecipeDateRefresh(date: $evaluationDate))
    }
}

private struct RecipeIngredientPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String?
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var search = ""
    @State private var stockFilter: IngredientStockFilter = .all
    @State private var filtersExpanded = false
    @State private var ingredientSort: IngredientPickerSort = .stocked
    @State private var category: IngredientCategory?
    @Environment(\.modelContext) private var context
    @State private var mappingCustom: CustomIngredient?
    @State private var mappingError: String?
    private var customFoods: [CustomIngredient] {
        customs.filter { food in
            let stockedCustom = stock.contains { $0.customIngredientID == food.id && StockExpiry.hasStock(StockLot($0)) && InventoryService.usable($0, on: .now) }
            let master = masters.first { $0.id == food.mappedIngredientMasterID }
            return !food.isDeleted && stock.contains { $0.customIngredientID == food.id && !$0.isDeleted }
                && (stockFilter == .all || (stockFilter == .stocked ? stockedCustom : !stockedCustom))
                && (category == nil || food.category == category)
                && IngredientSearch.matches(search, names: [food.name] + (master.map { [$0.canonicalName] + $0.aliases } ?? []))
        }.sorted { $0.name < $1.name }
    }
    private var stocked: Set<UUID> {
        Set(IngredientIdentity.snapshots(stock, customs: customs, masters: masters).filter { StockExpiry.hasStock($0) && StockExpiry.usable($0, on: .now) }.compactMap(\.masterID))
    }
    private var foods: [IngredientMaster] {
        let registered = stocked
        return masters.filter { $0.status == .active && $0.trackInventory
            && stockFilter.includes($0.id, stocked: registered) && (category == nil || $0.category == category)
            && IngredientSearch.matches(search, names: [$0.canonicalName] + $0.aliases) }
            .sorted { IngredientPickerOrder.precedes($0, $1, stocked: registered, sort: ingredientSort) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Button { filtersExpanded.toggle() } label: {
                            HStack {
                                if textSize.isAccessibilitySize {
                                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 22))
                                } else {
                                    Label(stockFilter == .all ? "絞り込み" : stockFilter.label,
                                          systemImage: "line.3.horizontal.decrease.circle")
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: filtersExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }.font(AppFont.subheadline).frame(minHeight: 44)
                        }.accessibilityLabel(stockFilter == .all ? "絞り込み" : stockFilter.label)
                            .accessibilityIdentifier("ingredient-filter-controls")
                            .accessibilityValue(filtersExpanded ? "開いています" : "閉じています")
                        Menu {
                            Picker("種類", selection: $category) {
                                Text("すべて").tag(Optional<IngredientCategory>.none)
                                ForEach(IngredientCategory.allCases.sorted { IngredientPickerOrder.rank($0) < IngredientPickerOrder.rank($1) }, id: \.self) {
                                    Label($0.label, systemImage: $0.symbol).tag(Optional($0))
                                }
                            }
                        } label: {
                            Text(category?.label ?? "種類").font(AppFont.subheadline)
                                .padding(.horizontal, 10).frame(minHeight: 44)
                                .background(AppTheme.accentSoft, in: Capsule())
                        }.accessibilityLabel("種類").accessibilityValue(category?.label ?? "すべて")
                            .accessibilityIdentifier("ingredient-category-filter")
                    }.buttonStyle(.borderless)
                    if filtersExpanded {
                        LabeledFilterMenu(title: "在庫", selection: $stockFilter, options: IngredientStockFilter.allCases, label: { $0.label })
                            .accessibilityIdentifier("ingredient-stock-filter")
                        if stockFilter != .all || category != nil || !search.isEmpty {
                            Button { stockFilter = .all; category = nil; search = "" } label: {
                                Label("解除", systemImage: "arrow.counterclockwise").font(AppFont.caption)
                            }.frame(minHeight: 44).accessibilityLabel("検索条件を解除").accessibilityIdentifier("ingredient-filters-clear")
                        }
                    }
                }
                if !customFoods.isEmpty {
                    Section("カスタム食材") {
                        ForEach(customFoods) { food in
                            Button {
                                if let master = masters.first(where: { $0.id == food.mappedIngredientMasterID && $0.status == .active && $0.trackInventory }) {
                                    selection = master.key; dismiss()
                                } else { mappingCustom = food }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.name)
                                    Text(masters.first { $0.id == food.mappedIngredientMasterID }?.canonicalName ?? "献立に使う食材を選ぶ")
                                        .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                                }.frame(minHeight: 44)
                            }.accessibilityIdentifier("recipe-custom-" + food.name)
                        }
                    }
                }
                if foods.isEmpty && customFoods.isEmpty { Text("該当する食材がありません。") }
                ForEach(foods) { food in
                    Button { selection = food.key; dismiss() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(food.canonicalName)
                            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
                            layout {
                                Label { Text(food.category.label) } icon: { IngredientCategoryIcon(category: food.category) }
                                if stocked.contains(food.id) { Label("冷蔵庫にある", systemImage: "refrigerator") }
                            }.font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                        }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44)
                    }.accessibilityIdentifier("recipe-ingredient-" + food.key)
                        .accessibilityAddTraits(selection == food.key ? .isSelected : [])
                }
            }.searchable(text: $search, prompt: "食材名・別名を探す")
                .onChange(of: search) { _, value in if !value.isEmpty { filtersExpanded = false } }
                .sheet(item: $mappingCustom) { food in
                    IngredientMappingPicker { master in
                        do {
                            try InventoryService(container: context.container).mapCustom(id: food.id, masterID: master.id)
                            selection = master.key; dismiss()
                        } catch { mappingError = error.localizedDescription }
                    }
                }
                .alert("対応付けできませんでした", isPresented: Binding(get: { mappingError != nil }, set: { if !$0 { mappingError = nil } })) {
                    Button("閉じる", role: .cancel) {}
                } message: { Text(mappingError ?? "") }
                .navigationTitle("食材を選ぶ").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("並び順", selection: $ingredientSort) {
                                ForEach(IngredientPickerSort.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                        } label: { Image(systemName: "arrow.up.arrow.down").frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("並べ替え").accessibilityValue(ingredientSort.label)
                            .accessibilityIdentifier("ingredient-sort")
                    }
                }
        }
    }
}

struct RecipeDetailView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let recipe: Recipe
    var plannedDate: Date? = nil
    var archivedMeal: MealSelection? = nil
    var onAdded: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @State private var servings = 1
    @State private var initializedServings = false
    @AppStorage(AppPreferences.defaultServings) private var preferredServings = 1
    @State private var showSteps = false
    @State private var checkedSteps = Set<Int>()
    @State private var error: String?
    @State private var inventoryPeek: RecipeStockPeekSelection?
    @State private var inventoryAddition: RecipeStockPeekSelection?
    @State private var completionCount: Int?
    private var completion: String? {
        completionCount.map { "買い物リストに\($0)品を追加しました。" }
    }
    @State private var addShortages = true
    @State private var cookingSession: MealSelection?
    @State private var cooking: MealSelection?
    @Query private var meals: [MealSelection]
    @State private var evaluationDate = Date.now
    private var suggestion: RecipeSuggestion {
        RecipeSuggestions.evaluate(recipe, foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
            stock: IngredientIdentity.snapshots(stock, customs: customs, masters: masters), servings: servings, on: plannedDate ?? evaluationDate)
    }
    var body: some View {
        let evaluation = suggestion
        ScrollViewReader { proxy in
            List {
                completionSection
                if let archivedMeal {
                    Section {
                        RecipeMealImage(height: 200, recipeKey: recipe.key)
                        Text(archivedMeal.recipeTitle).font(AppFont.title2.bold()).accessibilityIdentifier("recipe-detail-title")
                        Text("\(archivedMeal.servings)人分 · 約\(recipe.minutes)分")
                        Label(archivedMeal.state == "cooked" ? "作った料理" : "選んだ料理", systemImage: archivedMeal.state == "cooked" ? "checkmark.circle" : "calendar")
                        Picker("表示内容", selection: $showSteps) {
                            Text("使用材料").tag(false); Text("作り方").tag(true)
                        }.pickerStyle(.segmented).accessibilityIdentifier("recipe-detail-mode")
                    }
                    if showSteps { recipeBody(evaluation) }
                    else {
                        Section("保存した材料") {
                            if let ingredients = archivedMeal.plannedIngredients(recipes: [recipe]) {
                                ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ingredient in
                                    LabeledContent(masters.first { $0.key == ingredient.ingredientKey }?.canonicalName ?? ingredient.ingredientKey,
                                        value: ingredient.quantity.formatted() + ingredient.unit.label)
                                }
                                if ingredients.isEmpty { Text("材料の追加なし") }
                            } else { Text("材料を取得できません") }
                        }
                    }
                } else {
                    recipeHeader(evaluation)
                    recipeBody(evaluation)
                }
            }.scrollContentBackground(.hidden).background(AppTheme.background)
                .navigationTitle("レシピ詳細").navigationBarTitleDisplayMode(.inline)
                .modifier(RecipeDateRefresh(date: $evaluationDate))
                .onChange(of: servings) { _, _ in checkedSteps.removeAll() }
                .onAppear {
                    guard !initializedServings else { return }
                    servings = archivedMeal?.servings ?? selectedMeal?.servings ?? AppPreferences.validatedServings(preferredServings)
                    if archivedMeal != nil { showSteps = true }
                    initializedServings = true
                }
                .safeAreaInset(edge: .bottom) {
                    if archivedMeal == nil { selectionFooter }
                }
                .onChange(of: completionCount) { _, _ in
                    if typeSize.isAccessibilitySize {
                        withAnimation { proxy.scrollTo("recipe-completion", anchor: .top) }
                    }
                }
                .sheet(item: $cooking) { CookingView(meal: $0, recipe: recipe) }
                .sheet(item: $cookingSession) { MealCookingSessionView(meal: $0, recipe: recipe) }
                .sheet(item: $inventoryPeek) { selection in
                    RecipeInventoryPeek(ingredients: selection.ingredients)
                        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large]).presentationDragIndicator(.visible)
                }
                .sheet(item: $inventoryAddition) { selection in
                    RecipeInventoryAddition(ingredients: selection.ingredients)
                        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .alert("献立を決定できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("閉じる", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }
    @ViewBuilder private var completionSection: some View {
                if typeSize.isAccessibilitySize, let count = completionCount {
                    Section {
                        Text("買い物リストに\(count)品を追加しました。")
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(AppTheme.accent).id("recipe-completion")
                            .accessibilityIdentifier("recipe-completion")
                        if let meal = selectedMeal {
                            Button("作った・使用量を確認") { cooking = meal }.frame(minHeight: 44)
                                .accessibilityIdentifier("recipe-cook")
                        }
                    }
                }
    }
    @ViewBuilder private func recipeBody(_ evaluation: RecipeSuggestion) -> some View {
                if showSteps {
                    Section {
                        ForEach(recipe.steps) { step in
                            RecipeInstructionRow(step: step,
                                ingredients: recipe.instructionIngredients(for: step, servings: servings),
                                names: Dictionary(uniqueKeysWithValues: evaluation.ingredients.map { ($0.ingredient.ingredientKey, $0.name) }),
                                checked: checkedSteps.contains(step.order)) {
                                    if checkedSteps.contains(step.order) { checkedSteps.remove(step.order) }
                                    else { checkedSteps.insert(step.order) }
                                }
                        }
                    } header: {
                        Text("作り方 · \(servings)人分 · \(recipe.steps.count)ステップ")
                    } footer: {
                        Text("時間は目安。人数や器具、食材の状態に合わせて調整してください。")
                    }
                } else {
                    Section(selectedMeal?.isPrepared == true ? "レシピの材料" : "材料・冷蔵庫") {
                        ForEach(evaluation.ingredients) { assessed in
                            ingredientRow(assessed)
                        }
                    }
                }
    }
    private func recipeHeader(_ evaluation: RecipeSuggestion) -> some View {
                Section {
                    if let plannedDate { Label(MealPlanning.label(plannedDate) + "の献立", systemImage: "calendar").font(AppFont.subheadline).foregroundStyle(AppTheme.accent) }
                    RecipePhoto(suggestion: evaluation, height: typeSize.isAccessibilitySize ? 340 : 200, isPrepared: selectedMeal?.isPrepared == true, identifier: "recipe-detail")
                    Text(recipe.title).font(AppFont.title2.bold()).foregroundStyle(AppTheme.text).accessibilityIdentifier("recipe-detail-title")
                    RecipeMemo(text: recipe.summary).accessibilityIdentifier("recipe-memo")
                    RecipeTimeSummary(recipe: recipe)
                    Stepper("\(servings)人分", value: $servings, in: 1...4).accessibilityIdentifier("recipe-servings").disabled(selectedMeal != nil)
                    if selectedMeal?.isPrepared == true {
                        Label("作り置き · 材料の追加なし", systemImage: "checkmark.seal")
                            .font(AppFont.subheadline).foregroundStyle(AppTheme.accent).accessibilityIdentifier("recipe-prepared")
                    } else {
                        SuggestionSummaryView(suggestion: evaluation, showsTime: false, identifier: "recipe-detail",
                            onInventoryCheck: { inventoryPeek = RecipeStockPeekSelection(ingredients: evaluation.confirmation) },
                            onInventoryAdd: { inventoryAddition = RecipeStockPeekSelection(ingredients: evaluation.shortages) })
                    }
                    if !recipe.allergens.isEmpty {
                        Text("アレルゲン：" + recipe.allergens.map { allergenName($0) }.joined(separator: "、"))
                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    }
                    Picker("表示内容", selection: $showSteps) {
                        Text(selectedMeal?.isPrepared == true ? "レシピの材料" : "材料・在庫").tag(false); Text("作り方").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("recipe-detail-mode")
                }
    }
    @ViewBuilder private func ingredientRow(_ assessed: SuggestedIngredient) -> some View {
                            let ingredient = assessed.ingredient
                            let availability = assessed.availability
                            VStack(alignment: .leading, spacing: 6) {
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        Text(assessed.name).font(AppFont.headline)
                                        Spacer()
                                        Text("\(availability.required.formatted())\(ingredient.unit.label)").font(AppFont.subheadline)
                                    }
                                    VStack(alignment: .leading) {
                                        Text(assessed.name).font(AppFont.headline)
                                        Text("必要：\(availability.required.formatted())\(ingredient.unit.label)").font(AppFont.subheadline)
                                    }
                                }
                                if selectedMeal?.isPrepared != true {
                                    if availability.status == .confirmation {
                                        Button { inventoryPeek = RecipeStockPeekSelection(ingredients: [assessed]) } label: {
                                            Label(availability.label, systemImage: "exclamationmark.circle.fill")
                                                .font(AppFont.subheadline.weight(.medium)).foregroundStyle(AppTheme.warning)
                                                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10)
                                                .frame(minHeight: 44)
                                                .background(AppTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                                        }.buttonStyle(.plain).accessibilityLabel(assessed.name + "の在庫を確認")
                                            .accessibilityIdentifier("recipe-stock-peek-" + ingredient.ingredientKey)
                                    } else if availability.status == .shortage {
                                        Button { inventoryAddition = RecipeStockPeekSelection(ingredients: [assessed]) } label: {
                                            Label("買い足し：\(availability.shortage.formatted())\(ingredient.unit.label)", systemImage: "basket.fill")
                                                .font(AppFont.subheadline.weight(.medium)).foregroundStyle(AppTheme.accent)
                                                .padding(.horizontal, 10).frame(minHeight: 44)
                                                .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }.buttonStyle(.plain).accessibilityLabel(assessed.name + "を冷蔵庫に追加")
                                            .accessibilityValue("買い足し：\(availability.shortage.formatted())\(ingredient.unit.label)")
                                            .accessibilityHint("見つかった食材の在庫を登録")
                                            .accessibilityIdentifier("recipe-stock-add-" + ingredient.ingredientKey)
                                    } else {
                                        Label(availability.label, systemImage: "refrigerator")
                                            .font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                                    }
                                    if assessed.needsThawing || assessed.cookFromFrozen {
                                        Text(assessed.cookFromFrozen ? "凍ったまま使えます" : "解凍して使います")
                                            .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                                    }
                                }
                            }.padding(.vertical, 4)
    }
    private var selectionFooter: some View {
                    VStack(spacing: 8) {
                        if !typeSize.isAccessibilitySize, let completion {
                            Text(completion).font(AppFont.subheadline).foregroundStyle(AppTheme.accent)
                                .accessibilityIdentifier("recipe-completion")
                        }
                        if let meal = selectedMeal {
                            Button {
                                cookingSession = meal
                            } label: {
                                Label("作り方を見る", systemImage: "book.closed")
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(CoralPrimaryButtonStyle()).accessibilityIdentifier("recipe-start")
                            HStack(spacing: 16) {
                                Button {
                                    do { try MealService(container: context.container).cancel(mealID: meal.id); completionCount = nil }
                                    catch { self.error = error.localizedDescription }
                                } label: {
                                    MealActionLabel(title: "解除", symbol: "xmark.circle", color: AppTheme.danger)
                                }.frame(minHeight: 44).accessibilityIdentifier("recipe-cancel")
                                if !typeSize.isAccessibilitySize {
                                    Spacer()
                                    Button { cooking = meal } label: {
                                        MealActionLabel(title: "作った", symbol: "checkmark.circle", color: AppTheme.success)
                                    }.frame(minHeight: 44).accessibilityIdentifier("recipe-cook")
                                }
                            }
                        } else {
                            MealShoppingCheckbox(isOn: $addShortages, identifier: "recipe-add-shortages")
                            Button { select() } label: {
                                Text("献立に加える").fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(CoralPrimaryButtonStyle(fill: AppTheme.mealAddFill)).accessibilityIdentifier("recipe-select")
                        }
                    }.padding().background(AppTheme.background)
    }
    private var selectedMeal: MealSelection? {
        meals.first { $0.isActive && $0.recipeID == recipe.id && $0.plannedDay(on: evaluationDate) == MealPlanning.day(plannedDate ?? evaluationDate) }
    }
    private func select() {
        do {
            let count = try MealService(container: context.container).select(recipe: recipe, servings: servings, includeUncertain: false, scheduledDate: plannedDate, addShortagesToShopping: addShortages)
            completionCount = count
            onAdded?()
        } catch { self.error = error.localizedDescription }
    }
    private func allergenName(_ value: String) -> String {
        ["egg": "卵", "milk": "乳", "wheat": "小麦", "soy": "大豆", "sesame": "ごま", "chicken": "鶏肉",
         "pork": "豚肉", "beef": "牛肉", "salmon": "さけ", "mackerel": "さば"] [value] ?? value
    }
}

private struct RecipeStockPeekSelection: Identifiable {
    let id = UUID()
    let ingredients: [SuggestedIngredient]
}

private struct RecipeInventoryAddition: View {
    let ingredients: [SuggestedIngredient]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if ingredients.count == 1, let ingredient = ingredients.first {
                    RecipeInventoryAdditionForm(assessed: ingredient, onSaved: { dismiss() }, onCancel: { dismiss() })
                } else {
                    List(ingredients) { ingredient in
                        NavigationLink {
                            RecipeInventoryAdditionForm(assessed: ingredient, onSaved: { dismiss() }, onCancel: { dismiss() })
                        } label: {
                            HStack {
                                Text(ingredient.name).foregroundStyle(AppTheme.text)
                                Spacer()
                                Image(systemName: "refrigerator").foregroundStyle(AppTheme.accent)
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("recipe-stock-choose-" + ingredient.id)
                    }.scrollContentBackground(.hidden).background(AppTheme.background)
                        .navigationTitle("冷蔵庫に追加")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button("キャンセル") { dismiss() }.accessibilityIdentifier("recipe-stock-add-cancel")
                        } }
                }
            }.navigationBarTitleDisplayMode(.inline)
        }.tint(AppTheme.accent)
    }
}

private struct RecipeInventoryAdditionForm: View {
    @AppStorage(AppPreferences.mergeInventory) private var mergeInventory = true
    let assessed: SuggestedIngredient
    let onSaved: () -> Void
    let onCancel: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var masters: [IngredientMaster]
    @Query private var customs: [CustomIngredient]
    @Query private var stock: [InventoryItem]
    @State private var exact = false
    @State private var quantity = ""
    @State private var unit: IngredientUnit = .gram
    @State private var rough: RoughStockState = .available
    @State private var storage: StorageMethod = .refrigerated
    @State private var initialized = false
    @State private var saving = false
    @State private var error: String?
    @FocusState private var quantityFocused: Bool
    private var master: IngredientMaster? {
        masters.first { $0.key == assessed.ingredient.ingredientKey && $0.trackInventory && $0.status == .active }
    }
    private var presenceOnly: Bool { master?.category == .seasoning || assessed.ingredient.inventoryMode == "presence" }
    private var lots: [InventoryItem] {
        guard let master else { return [] }
        return stock.filter { !$0.isDeleted && IngredientIdentity.masterID(for: $0, customs: customs, masters: masters) == master.id }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }
    private var valid: Bool {
        guard let master else { return false }
        return !exact || presenceOnly || (StorePurchasePlan.parseQuantity(quantity) != nil && master.allowedUnits.contains(unit))
    }
    var body: some View {
        Form {
            Section {
                Text(assessed.name).font(AppFont.title2.bold()).foregroundStyle(AppTheme.text)
                Text("レシピ：" + assessed.availability.required.formatted() + assessed.ingredient.unit.label)
                    .font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                if !presenceOnly {
                    Picker("登録方法", selection: $exact) {
                        Text("状態").tag(false); Text("数量").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("recipe-stock-add-mode")
                }
                if exact && !presenceOnly {
                    ViewThatFits(in: .horizontal) {
                        HStack { quantityField; unitPicker }
                        VStack(alignment: .leading) { quantityField; unitPicker }
                    }
                } else {
                    Picker("在庫", selection: $rough) {
                        Text("あり").tag(RoughStockState.available)
                        Text("少なめ").tag(RoughStockState.low)
                        Text("なし").tag(RoughStockState.unavailable)
                    }.pickerStyle(.segmented).accessibilityIdentifier("recipe-stock-add-state")
                }
                Picker("保存場所", selection: $storage) {
                    ForEach(StorageMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }.accessibilityIdentifier("recipe-stock-add-storage")
            }
            if !lots.isEmpty {
                Section {
                    ForEach(lots) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(amountLabel(item)).font(AppFont.headline)
                            Text(item.storage.label + " · " + expiryLabel(item)).font(AppFont.caption)
                                .foregroundStyle(StockExpiry.usable(StockLot(item), on: .now) ? AppTheme.secondary : AppTheme.danger)
                        }.accessibilityElement(children: .combine)
                            .accessibilityIdentifier("recipe-stock-existing-" + item.id.uuidString)
                    }
                } header: { Text("現在の冷蔵庫") }
                  footer: { Text("見つかった分を追加します。") }
            }
            if master == nil { Text("食材を取得できません。画面を開き直してください。").foregroundStyle(AppTheme.danger) }
        }.scrollContentBackground(.hidden).background(AppTheme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("冷蔵庫に追加")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("キャンセル", action: onCancel).accessibilityIdentifier("recipe-stock-add-cancel")
            } }
            .onAppear {
                guard !initialized, let master else { return }
                unit = master.allowedUnits.contains(assessed.ingredient.unit) ? assessed.ingredient.unit : master.defaultUnit
                storage = master.defaultStorage
                initialized = true
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Label("追加", systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(CoralPrimaryButtonStyle()).disabled(!valid || saving)
                    .accessibilityLabel(assessed.name + "を冷蔵庫に追加")
                    .accessibilityIdentifier("recipe-stock-add-save")
                    .padding().background(AppTheme.background)
            }
            .alert("追加できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
    private var quantityField: some View {
        TextField("追加分の量", text: $quantity).keyboardType(.decimalPad).focused($quantityFocused)
            .accessibilityIdentifier("recipe-stock-add-quantity").frame(minHeight: 44)
    }
    private var unitPicker: some View {
        Picker("単位", selection: $unit) {
            ForEach(master?.allowedUnits ?? [], id: \.self) { Text($0.label).tag($0) }
        }.accessibilityIdentifier("recipe-stock-add-unit")
    }
    private func save() {
        guard valid, !saving, let master else { return }
        saving = true
        quantityFocused = false
        do {
            let amount: StockAmount
            if exact && !presenceOnly {
                guard let value = StorePurchasePlan.parseQuantity(quantity) else { saving = false; return }
                amount = .exact(value, unit)
            } else { amount = .rough(rough) }
            try InventoryService(container: context.container, mergeDuplicates: mergeInventory).save(InventoryDraft(masterID: master.id, amount: amount, storage: storage))
            onSaved()
        } catch { saving = false; self.error = error.localizedDescription }
    }
}

private struct RecipeInventoryPeek: View {
    let ingredients: [SuggestedIngredient]
    @Environment(\.dismiss) private var dismiss
    @Query private var masters: [IngredientMaster]
    @Query private var customs: [CustomIngredient]
    @Query private var stock: [InventoryItem]
    private func lots(for assessed: SuggestedIngredient) -> [InventoryItem] {
        guard let master = masters.first(where: { $0.key == assessed.ingredient.ingredientKey }) else { return [] }
        return stock.filter {
            !$0.isDeleted && IngredientIdentity.masterID(for: $0, customs: customs, masters: masters) == master.id
        }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(ingredients) { assessed in
                    Section(ingredients.count == 1 ? "現在の冷蔵庫" : assessed.name) {
                        LabeledContent("レシピで使う量", value: assessed.availability.required.formatted() + assessed.ingredient.unit.label)
                        let items = lots(for: assessed)
                        if items.isEmpty { Text("登録された在庫はありません") }
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(amountLabel(item)).font(AppFont.headline).foregroundStyle(AppTheme.text)
                                Label(item.storage.label, systemImage: item.storage == .frozen ? "snowflake" : "refrigerator")
                                    .font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                                Text(expiryLabel(item)).font(AppFont.caption)
                                    .foregroundStyle(!StockExpiry.usable(StockLot(item), on: .now) ? AppTheme.danger : AppTheme.secondary)
                                if let custom = customs.first(where: { $0.id == item.customIngredientID }) {
                                    Text(custom.name).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                                }
                            }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                                .accessibilityIdentifier("recipe-stock-lot-" + item.id.uuidString)
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(AppTheme.background)
                .navigationTitle(ingredients.count == 1 ? ingredients[0].name + "の在庫" : "冷蔵庫の在庫").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("recipe-stock-peek-close")
                } }
        }
    }
}

struct MealShoppingCheckbox: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var isOn: Bool
    let identifier: String
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square").accessibilityHidden(true)
                Text(typeSize.isAccessibilitySize ? "買い物に追加" : "不足分を買い物リストに追加").font(AppFont.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
            .accessibilityLabel("不足分を買い物リストに追加")
            .accessibilityValue(isOn ? "オン" : "オフ").accessibilityIdentifier(identifier)
    }
}

private struct RecipeTimeSummary: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let recipe: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("調理時間の目安", systemImage: "clock").font(AppFont.subheadline)
                .foregroundStyle(AppTheme.secondary)
            Text("合計 約\(recipe.minutes)分")
                .font(AppFont.title2.bold()).foregroundStyle(AppTheme.accent)
                .accessibilityIdentifier("recipe-time-total")
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 20))
            layout {
                Label("準備 \(recipe.prepMinutes)分", systemImage: "carrot")
                    .accessibilityIdentifier("recipe-time-prep")
                Label("調理 \(recipe.cookMinutes)分", systemImage: "frying.pan")
                    .accessibilityIdentifier("recipe-time-cook")
            }.font(AppFont.subheadline).foregroundStyle(AppTheme.text)
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SuggestionSummaryView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let suggestion: RecipeSuggestion
    var compact = false
    var showsTime = true
    let identifier: String
    var onInventoryCheck: (() -> Void)? = nil
    var onInventoryAdd: (() -> Void)? = nil
    private var matchText: String {
        compact ? "\(Int(suggestion.coverage * 100))%（\(suggestion.matchedCount)/\(suggestion.comparisonIngredients.count)品）" : suggestion.matchLabel
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if typeSize.isAccessibilitySize {
                    metricsStack
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            if showsTime { metric("\(suggestion.recipe.minutes)分", icon: "clock") }
                            metric(matchText, icon: "refrigerator")
                        }
                        metricsStack
                    }
                }
            }.accessibilityRepresentation { Text((showsTime ? "\(suggestion.recipe.minutes)分 · " : "") + suggestion.matchLabel) }
                .accessibilityIdentifier(identifier + "-match")
            if let planned = suggestion.plannedLabel {
                Text(planned).font(AppFont.caption).foregroundStyle(AppTheme.accent)
                    .accessibilityIdentifier(identifier + "-planned")
            }
            if let amount = suggestion.plannedAmountLabel {
                Text(amount).font(AppFont.caption).foregroundStyle(suggestion.plannedAvailability?.status == .available ? AppTheme.accent : AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier + "-planned-amount")
            }
            if let shortage = suggestion.shortageLabel {
                if let onInventoryAdd {
                    Button(action: onInventoryAdd) {
                        Label(shortage, systemImage: "basket.fill").font(AppFont.caption.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).frame(minHeight: 44)
                            .background(AppTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                        .accessibilityHint("見つかった食材を冷蔵庫に追加")
                        .accessibilityIdentifier(identifier + "-shortages")
                } else {
                    Label(shortage, systemImage: "basket.fill").font(AppFont.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier + "-shortages")
                }
            }
            if let confirmation = suggestion.confirmationLabel {
                if let onInventoryCheck {
                    Button(action: onInventoryCheck) {
                        Label(confirmation, systemImage: "exclamationmark.circle.fill")
                            .font(AppFont.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(AppTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).foregroundStyle(AppTheme.warning)
                        .accessibilityHint("現在の冷蔵庫の在庫を表示")
                        .accessibilityIdentifier(identifier + "-confirmation")
                } else {
                    Label(confirmation, systemImage: "exclamationmark.circle").font(AppFont.caption).foregroundStyle(AppTheme.warning)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(identifier + "-confirmation")
                }
            }
            if !compact {
                if let thawing = suggestion.thawingLabel { Text(thawing).font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
                if let frozen = suggestion.frozenCookingLabel { Text(frozen).font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
            }
        }
    }
    private var metricsStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTime { metric("\(suggestion.recipe.minutes)分", icon: "clock") }
            metric(matchText, icon: "refrigerator")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(compact ? AppFont.caption : AppFont.subheadline)
            .foregroundStyle(AppTheme.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct RecipeCandidateRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let suggestion: RecipeSuggestion
    let identifier: String
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            if typeSize.isAccessibilitySize {
                RecipePhoto(suggestion: suggestion, height: 340, identifier: identifier)
            } else {
                RecipePhoto(suggestion: suggestion, height: 76, thumbnail: true, identifier: identifier).frame(width: 76)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(suggestion.recipe.title).font(AppFont.headline).foregroundStyle(AppTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !typeSize.isAccessibilitySize {
                    Text([RecipeKind.main, .side, .soup].first { $0.includes(suggestion.recipe) }?.label ?? "料理")
                        .font(AppFont.caption2.weight(.medium)).foregroundStyle(AppTheme.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(AppTheme.background, in: Capsule())
                }
                SuggestionSummaryView(suggestion: suggestion, compact: true, identifier: identifier)
            }
        }.padding(.vertical, 6).frame(minHeight: 44)
    }
}

struct RecipeDateRefresh: ViewModifier {
    @Binding var date: Date
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.onAppear { refresh() }
            .onChange(of: scenePhase) { if scenePhase == .active { refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in date = .now }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { refresh(at: $0) }
    }
    private func refresh(at now: Date = .now) {
        if !Calendar.current.isDate(date, inSameDayAs: now) { date = now }
    }
}
struct SuggestionExplanationView: View {
    var body: some View {
        List {
            Section("おすすめの順番") {
                Text("選んだ料理の種類から、材料の一致度が高い順に表示します。")
                Text("同じ一致度なら、量の確認が少ない料理、調理時間が短い料理を優先します。")
                Text("設定した人数で評価し、詳細でも人数を変更できます。")
            }
            Section("一致と必要量") {
                Text("「食材あり」は必要量を保証しません。必要量はレシピで見られます。量が不明な食材は、選んだときだけ買い物リストに追加します。")
                Text("調理後に残量を記録できます。記録せずに完了することもできます。任意材料や水は一致度に含みません。")
            }
            Section("期限と冷凍食材") {
                Text("期限切れと取り除いた食材は献立の計算から除外します。期限が近い食材はホームの独立した一覧で確認できます。")
                Text("冷凍食材も在庫に含めます。解凍が必要か、凍ったまま調理できるかを表示します。解凍が必要な場合は、表示の調理時間に加えて余裕を持って選んでください。")
            }
        }.scrollContentBackground(.hidden).background(AppTheme.background).navigationTitle("おすすめの見方")
    }
}


private struct RecipeInstructionRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let step: Recipe.Step
    let ingredients: [Recipe.InstructionIngredient]
    let names: [String: String]
    let checked: Bool
    let toggle: () -> Void
    private var ingredientText: String {
        ingredients.map { use in
            let ingredient = use.ingredient
            let amount = use.quantity.formatted(.number.precision(.fractionLength(0...3)))
            let quantity = [.tablespoon, .teaspoon].contains(ingredient.unit)
                ? ingredient.unit.label + amount : amount + ingredient.unit.label
            return (names[ingredient.ingredientKey] ?? ingredient.ingredientKey) + " " + quantity
                + (ingredient.requirement == "optional" ? "（お好み）" : "")
        }.joined(separator: " ／ ")
    }
    private var timeLabel: String { step.timerMinutes.map { "約\($0)分" } ?? "" }
    private var spokenLabel: String {
        ["手順\(step.order)", step.title ?? "", timeLabel].filter { !$0.isEmpty }.joined(separator: "、")
    }
    private var ingredientBox: some View {
        Text(ingredientText).font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.accent.opacity(0.07)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: toggle) {
                    Image(systemName: checked ? "checkmark.circle.fill" : "\(step.order).circle")
                        .resizable().scaledToFit().frame(width: 26, height: 26)
                        .foregroundStyle(AppTheme.accent).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(spokenLabel)
                    .accessibilityValue(checked ? "完了" : "未完了")
                    .accessibilityHint(checked ? "タップで未完了に戻す" : "タップで完了にする")
                    .accessibilityIdentifier("recipe-step-\(step.order)")
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                layout {
                    Text(step.title ?? "手順\(step.order)").font(AppFont.headline).foregroundStyle(AppTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    if step.timerMinutes != nil {
                        Label(timeLabel, systemImage: "clock").labelStyle(.titleAndIcon)
                            .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }.padding(.top, 8)
            }
            ingredientBox.accessibilityIdentifier("recipe-step-ingredients-\(step.order)")
            Text(step.text).foregroundStyle(AppTheme.text).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recipe-step-text-\(step.order)")
            if let note = step.timeNote {
                Text(note).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recipe-step-note-\(step.order)")
            }
            if let tip = step.tip {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb").resizable().scaledToFit().frame(width: 16, height: 16)
                        Text("ポイント").font(AppFont.caption.weight(.semibold))
                    }.foregroundStyle(AppTheme.accent)
                    Text(tip).font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("recipe-step-tip-\(step.order)")
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}


struct MealActionLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var body: some View {
        Label(title, systemImage: symbol).font(AppFont.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(color).background(color.opacity(0.13), in: Capsule())
    }
}

private struct MealRecipePage: Identifiable {
    let meal: MealSelection
    let recipe: Recipe
    var id: UUID { meal.id }
}

struct MealCookingSessionView: View {
    private let plannedDay: Date
    private let recipes: [Recipe]
    @Query(sort: \MealSelection.date, order: .reverse) private var meals: [MealSelection]
    @Query private var masters: [IngredientMaster]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedID: UUID
    @State private var checked: [UUID: Set<Int>] = [:]
    @State private var finishing: MealRecipePage?
    @State private var completedID: UUID?

    init(meal: MealSelection, recipe: Recipe, recipes: [Recipe]? = nil) {
        // Detail can open from any recipe list. Include its supplied recipe even if catalog loading fails.
        self.recipes = recipes ?? ((try? RecipeCatalog.load()) ?? []).filter { $0.id != recipe.id } + [recipe]
        self.plannedDay = meal.plannedDay()
        _selectedID = State(initialValue: meal.id)
    }
    private var pages: [MealRecipePage] {
        meals.filter { $0.isActive && $0.plannedDay() == plannedDay }.compactMap { meal in
            recipes.first { $0.id == meal.recipeID }.map { MealRecipePage(meal: meal, recipe: $0) }
        }
    }
    private var current: MealRecipePage? { pages.first { $0.id == selectedID } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if pages.count > 1 { recipeTabs }
                TabView(selection: $selectedID) {
                    ForEach(pages) { page in
                        instructions(page).tag(page.id)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .accessibilityIdentifier("meal-recipe-pages")
            }.background(AppTheme.background)
                .navigationTitle("作り方").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
                .safeAreaInset(edge: .bottom) { completionButton }
                .sheet(item: $finishing, onDismiss: finishDismissed) { page in
                    // Freeze the target before showing the editor, independently of pager selection/query updates.
                    CookingView(meal: page.meal, recipe: page.recipe, onCompleted: { completedID = page.id })
                }
                .onChange(of: pages.map(\.id)) { _, ids in
                    if !ids.contains(selectedID), let next = ids.first { selectedID = next }
                }
        }
    }
    private var recipeTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        Button { withAnimation { selectedID = page.id } } label: {
                            Text(typeSize.isAccessibilitySize ? "\(index + 1)品目" : page.recipe.title)
                                .font(AppFont.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(selectedID == page.id ? AppTheme.accent : AppTheme.secondary)
                                .background(selectedID == page.id ? AppTheme.accent.opacity(0.14) : AppTheme.surface, in: Capsule())
                                .fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
                        }.buttonStyle(.plain).id(page.id)
                            .accessibilityLabel(page.recipe.title)
                            .accessibilityAddTraits(selectedID == page.id ? .isSelected : [])
                            .accessibilityValue("\(index + 1) / \(pages.count)品")
                            .accessibilityIdentifier("meal-recipe-tab-" + page.recipe.key)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 4)
            }.onAppear { proxy.scrollTo(selectedID, anchor: .center) }
                .onChange(of: selectedID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
        }
    }
    private func instructions(_ page: MealRecipePage) -> some View {
        List {
            Section {
                Text(page.recipe.title).font(AppFont.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("meal-session-title-" + page.recipe.key)
                Label("\(page.meal.servings)人分 · 約\(page.recipe.minutes)分", systemImage: "clock")
                    .foregroundStyle(AppTheme.secondary).accessibilityIdentifier("meal-session-servings-" + page.recipe.key)
            }
            Section("作り方") {
                ForEach(page.recipe.steps) { step in
                    RecipeInstructionRow(step: step,
                        ingredients: page.recipe.instructionIngredients(for: step, servings: page.meal.servings),
                        names: Dictionary(uniqueKeysWithValues: masters.map { ($0.key, $0.canonicalName) }),
                        checked: checked[page.id, default: []].contains(step.order)) {
                            if checked[page.id, default: []].contains(step.order) { checked[page.id, default: []].remove(step.order) }
                            else { checked[page.id, default: []].insert(step.order) }
                        }
                }
            }
        }.scrollContentBackground(.hidden).background(AppTheme.background)
            .accessibilityIdentifier("meal-instructions-" + page.recipe.key)
    }
    @ViewBuilder private var completionButton: some View {
        if let page = current {
            Button { completedID = nil; finishing = page } label: {
                Label("作った", systemImage: "checkmark.circle").font(AppFont.headline)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(AppTheme.success).foregroundStyle(AppTheme.surface)
                .padding().background(AppTheme.background)
                .accessibilityLabel(page.meal.isPrepared ? "作り置きを完了" : "作った・在庫を確認").accessibilityIdentifier("meal-session-finish")
                .accessibilityHint(page.meal.isPrepared ? "材料の在庫は変更しません" : page.recipe.title + "の在庫を確認します")
        }
    }
    private func finishDismissed() {
        guard completedID != nil else { return }
        completedID = nil
        if let next = pages.first { selectedID = next.id }
        else { dismiss() }
    }
}
