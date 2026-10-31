import SwiftUI
import SwiftData

private struct MealAdditionRequest: Identifiable {
    let id = UUID()
    let course: MealCourse?
    let day: Date
}

struct MealPlanView: View {
    let recipes: [Recipe]
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \MealSelection.date) private var meals: [MealSelection]
    @Query private var stock: [InventoryItem]
    @Query private var masters: [IngredientMaster]
    @Query private var customs: [CustomIngredient]
    @State private var now = Date.now
    // Nil follows today across midnight; an explicit selection stays on that calendar day.
    @State private var selectedDate: Date?
    @State private var showArchive = false
    @State private var adding: MealAdditionRequest?
    @State private var trayRecipeID: UUID?
    @State private var cooking: MealSelection?
    @State private var session: MealSelection?
    @State private var error: String?
    private var selectedDay: Date { MealPlanning.selectedDay(selectedDate, now: now) }
    private var isArchive: Bool { selectedDay < MealPlanning.day(now) }
    private var active: [MealSelection] { meals.filter(\.isActive) }
    private var visible: [MealSelection] {
        meals.filter { ($0.isActive || (isArchive && $0.state == "cooked")) && $0.plannedDay(on: now) == selectedDay }
    }
    private var summary: MealMaterialSummary {
        let plans = (isArchive ? visible : active).map { meal in
            let ingredients = meal.plannedIngredients(recipes: recipes)
            return PlannedMeal(id: meal.id, day: meal.plannedDay(on: now), createdAt: meal.date,
                ingredients: ingredients ?? [], hasKnownIngredients: ingredients != nil)
        }
        return MealPlanning.summarize(plans, visibleIDs: Set(visible.map(\.id)),
            foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
            stock: IngredientIdentity.snapshots(stock, customs: customs, masters: masters), assessAvailability: !isArchive)
    }
    private var periodTitle: String { MealPlanning.title(for: selectedDay, now: now) }
    var body: some View {
        let materials = summary
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(periodTitle).font(AppFont.title2.bold()).foregroundStyle(AppTheme.text)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("meal-plan-day-title")
                            Spacer(minLength: 8)
                            if selectedDate != nil {
                                Button("今日へ") { selectedDate = nil }.font(AppFont.subheadline).frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("meal-return-today")
                            }
                        }
                        MealTrayView(recipes: recipes, meals: visible, allowsAdding: !isArchive, add: { course in
                            guard !isArchive else { return }
                            adding = MealAdditionRequest(course: course, day: selectedDay)
                        }, open: { recipe in
                            trayRecipeID = recipe.id
                        })
                    }.listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    NavigationLink {
                        MealMaterialsView(recipes: recipes, day: selectedDay, isArchive: isArchive)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(isArchive ? "使用材料" : typeSize.isAccessibilitySize ? "材料・不足" : "使用材料・不足", systemImage: "basket")
                                .symbolVariant(.none).font(AppFont.headline)
                            if typeSize.isAccessibilitySize {
                                Text(isArchive ? "\(visible.count)品 · 材料\(materials.materials.count)種類" : "\(visible.count)品 · 不足\(materials.shortages.count)").font(AppFont.caption)
                                    .foregroundStyle(AppTheme.secondary)
                                if materials.incomplete { Image(systemName: "exclamationmark.triangle").foregroundStyle(AppTheme.warning) }
                            } else {
                                Text("\(visible.count)品の料理 · 材料\(materials.materials.count)種類")
                                    .font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                                if materials.incomplete {
                                    Label("材料を取得できない料理があります", systemImage: "exclamationmark.triangle")
                                        .font(AppFont.caption).foregroundStyle(AppTheme.warning)
                                }
                                if isArchive {
                                    Text("保存した献立の材料").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                                } else if !materials.shortages.isEmpty || !materials.confirmation.isEmpty {
                                    Text("不足 \(materials.shortages.count)種類 · 量を確認 \(materials.confirmation.count)種類")
                                        .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppTheme.warning)
                                } else if !materials.materials.isEmpty && !materials.incomplete {
                                    Label("在庫でそろっています", systemImage: "checkmark.circle")
                                        .foregroundStyle(AppTheme.success).font(AppFont.subheadline)
                                }
                            }
                        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                    }.accessibilityLabel("使用材料・不足、\(visible.count)品の料理、材料\(materials.materials.count)種類、不足\(materials.shortages.count)種類、量を確認\(materials.confirmation.count)種類")
                        .accessibilityIdentifier("meal-plan-materials")
                }
                if !visible.isEmpty {
                    Section(isArchive ? "保存した料理" : "選んだ料理") { ForEach(visible) { mealRow($0, readOnly: isArchive) } }
                }
                let completed = meals.filter { $0.state == "cooked" && $0.plannedDay(on: now) == selectedDay }
                if !isArchive && !completed.isEmpty {
                    Section("作った料理") {
                        ForEach(completed) { mealRow($0, readOnly: true) }
                    }
                }
            }.scrollContentBackground(.hidden).background(AppTheme.background)
                .modifier(PageHeading(title: "献立", icon: "calendar"))
                .modifier(RecipeDateRefresh(date: $now))
                .safeAreaInset(edge: .top, spacing: 0) { dateStrip }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showArchive = true } label: { FlatToolbarIcon(systemName: "calendar") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("過去の献立を見る").accessibilityIdentifier("meal-archive-open")
                    }.flatToolbarBackground()
                }
                .navigationDestination(item: $trayRecipeID) { id in
                    if let recipe = recipes.first(where: { $0.id == id }) {
                        RecipeDetailView(recipe: recipe, plannedDate: selectedDay,
                            archivedMeal: isArchive ? visible.first { $0.recipeID == id } : nil)
                    }
                }
                .sheet(item: $adding) { request in
                    MealRecipePicker(recipes: recipes, day: request.day, course: request.course)
                }
                .sheet(isPresented: $showArchive) {
                    MealArchivePicker(meals: meals, now: now) { selectedDate = $0; showArchive = false }
                }
                .sheet(item: $session) { meal in
                    if let recipe = recipes.first(where: { $0.id == meal.recipeID }) {
                        MealCookingSessionView(meal: meal, recipe: recipe, recipes: recipes)
                    }
                }
                .sheet(item: $cooking) { meal in
                    if let recipe = recipes.first(where: { $0.id == meal.recipeID }) { CookingView(meal: meal, recipe: recipe) }
                }
                .alert("献立を更新できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("閉じる", role: .cancel) {}
                } message: { Text(error ?? "") }
        }
    }
    private var dateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if typeSize.isAccessibilitySize { dateButtons }
            else { dateButtons.containerRelativeFrame(.horizontal) }
        }.contentMargins(.horizontal, 12, for: .scrollContent)
            .contentMargins(.vertical, 8, for: .scrollContent)
            .background(AppTheme.background).accessibilityIdentifier("meal-day-strip")
    }
    private var dateButtons: some View {
        HStack(spacing: 0) {
            ForEach(Array(MealPlanning.days(from: now).enumerated()), id: \.element) { index, day in
                Button { selectedDate = index == 0 ? nil : day } label: {
                    VStack(spacing: 2) {
                        Text(index == 0 ? "今日" : day.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).weekday(.abbreviated)))
                            .font(AppFont.caption)
                        Text(String(Calendar.current.component(.day, from: day)))
                            .font(AppFont.custom(18, relativeTo: .title3)).monospacedDigit()
                    }.fixedSize(horizontal: typeSize.isAccessibilitySize, vertical: true)
                        .padding(.horizontal, 4).padding(.vertical, 6)
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(selectedDay == day ? AppTheme.accent : AppTheme.secondary)
                        .background {
                            if selectedDay == day {
                                AppCardSurface(cornerRadius: 12, shadow: .selectedDay, fill: AppTheme.accentSoft)
                            }
                        }
                        .padding(.horizontal, 3)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(MealPlanning.label(day) + (index == 0 ? "、今日" : ""))
                    .accessibilityValue(selectedDay == day ? "選択中" : "")
                    .accessibilityIdentifier("meal-day-\(index)")
                    .overlay(alignment: .trailing) {
                        if index < 6 {
                            Rectangle().fill(AppTheme.border.opacity(0.65)).frame(width: 0.5, height: 28)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
            }
        }
    }
    private func cancel(_ meal: MealSelection) {
        do { try MealService(container: context.container).cancel(mealID: meal.id) }
        catch { self.error = error.localizedDescription }
    }
    private func mealRow(_ meal: MealSelection, readOnly: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recipe = recipes.first(where: { $0.id == meal.recipeID }) {
                NavigationLink { RecipeDetailView(recipe: recipe, plannedDate: meal.plannedDay(on: now), archivedMeal: readOnly ? meal : nil) } label: {
                    HStack(spacing: 12) {
                        RecipeMealImage(height: 48, recipeKey: recipe.key).frame(width: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.recipeTitle).font(AppFont.headline)
                            Text(meal.isPrepared ? "作り置き · \(meal.servings)人分" : "\(meal.servings)人分 · 約\(recipe.minutes)分")
                                .font(AppFont.caption).foregroundStyle(meal.isPrepared ? AppTheme.accent : AppTheme.secondary)
                            if readOnly { Text(meal.state == "cooked" ? "作った" : "未調理").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("meal-detail-" + meal.recipeID.uuidString)
                if !readOnly {
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                    Button { session = meal } label: { Label("作り方を見る", systemImage: "book.closed").font(AppFont.subheadline) }
                        .frame(minHeight: 44).accessibilityIdentifier("meal-start-" + meal.recipeID.uuidString)
                    Button { cooking = meal } label: { MealActionLabel(title: "作った", symbol: "checkmark.circle", color: AppTheme.success) }
                        .frame(minHeight: 44).accessibilityIdentifier("meal-cook")
                    Button { cancel(meal) } label: { MealActionLabel(title: "解除", symbol: "xmark.circle", color: AppTheme.danger) }
                        .frame(minHeight: 44).accessibilityIdentifier("meal-cancel-" + meal.recipeID.uuidString)
                    }.buttonStyle(.borderless).frame(minHeight: 44)
                }
            } else {
                Text(meal.recipeTitle)
                Label("レシピが見つかりません", systemImage: "exclamationmark.triangle").font(AppFont.caption)
                if !readOnly { Button("解除") { cancel(meal) }.frame(minHeight: 44) }
            }
        }.padding(.vertical, 4)
    }
}

private struct MealArchivePicker: View {
    let meals: [MealSelection]
    let now: Date
    let select: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    private var lastDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: MealPlanning.day(now))! }
    private var savedDays: [Date] {
        Set(meals.filter { $0.isActive || $0.state == "cooked" }.map { $0.plannedDay(on: now) }
            .filter { $0 < MealPlanning.day(now) }).sorted(by: >)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("日付", selection: $date, in: ...lastDay, displayedComponents: .date)
                        .datePickerStyle(.graphical).accessibilityIdentifier("meal-archive-calendar")
                    Button("この日の献立を見る") { select(MealPlanning.day(date)) }
                        .frame(minHeight: 44).accessibilityIdentifier("meal-archive-select")
                }
                Section("保存した献立") {
                    if savedDays.isEmpty { Text("過去の献立はまだありません") }
                    ForEach(Array(savedDays.enumerated()), id: \.element) { index, day in
                        Button { select(day) } label: {
                            HStack {
                                Text(MealPlanning.label(day))
                                Spacer(minLength: 8)
                                Text("\(meals.filter { ($0.isActive || $0.state == "cooked") && $0.plannedDay(on: now) == day }.count)品")
                                    .foregroundStyle(AppTheme.secondary)
                            }.frame(minHeight: 44)
                        }.accessibilityIdentifier("meal-archive-saved-\(index)")
                    }
                }
            }.scrollContentBackground(.hidden).background(AppTheme.background)
                .navigationTitle("過去の献立").navigationBarTitleDisplayMode(.inline)
                .onAppear { date = savedDays.first ?? lastDay }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("meal-archive-close")
                } }
        }
    }
}

/// A code-drawn tray and plates adapt to text size without introducing new photo assets.
private struct MealTrayView: View {
    let recipes: [Recipe]
    let meals: [MealSelection]
    var allowsAdding = true
    let add: (MealCourse) -> Void
    let open: (Recipe) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    private var wood: Color {
        scheme == .dark ? Color(red: 0.30, green: 0.22, blue: 0.17) : Color(red: 0.87, green: 0.73, blue: 0.56)
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 20) {
                    ForEach(MealCourse.allCases) { course in accessibleSlot(course) }
                    TrayChopsticks().frame(width: 190, height: 20).padding(.top, 8)
                }.padding(18)
            } else {
                GeometryReader { geometry in
                    let size = geometry.size
                    ZStack {
                        TrayWoodGrain().stroke(wood.opacity(0.22), lineWidth: 1).padding(10)
                            .accessibilityHidden(true)
                        ForEach(MealCourse.allCases) { course in
                            wideSlot(course, size: size)
                        }
                        TrayChopsticks().frame(width: size.width * 0.68, height: 14)
                            .position(x: size.width * 0.50, y: size.height * 0.96)
                        // Carved handles at the sides of the serving tray.
                        ForEach([0.027, 0.973], id: \.self) { x in
                            Capsule().fill(wood.opacity(0.55)).frame(width: 4, height: 25)
                                .position(x: size.width * x, y: size.height * 0.48)
                                .accessibilityHidden(true)
                        }
                    }
                }.aspectRatio(1.35, contentMode: .fit)
            }
        }
            .background {
                RoundedRectangle(cornerRadius: 26).fill(wood.gradient)
                    .overlay { RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.28), lineWidth: 2).padding(6) }
                    .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(wood.opacity(0.7), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
            }
    }
    private func selections(for course: MealCourse) -> [MealSelection] {
        meals.filter { meal in
            recipes.first(where: { $0.id == meal.recipeID }).map { MealCourse.of($0) == course } ?? false
        }
    }
    private func wideSlot(_ course: MealCourse, size: CGSize) -> some View {
        let selections = selections(for: course)
        let recipe = selections.first.flatMap { meal in recipes.first { $0.id == meal.recipeID } }
        let dishSize: CGSize = switch course {
        case .main: CGSize(width: size.width * 0.40, height: size.width * 0.40)
        case .side: CGSize(width: size.width * 0.20, height: size.width * 0.17)
        case .staple: CGSize(width: size.width * 0.29, height: size.width * 0.29)
        case .soup: CGSize(width: size.width * 0.23, height: size.width * 0.23)
        }
        let center: CGPoint = switch course {
        case .main: CGPoint(x: size.width * 0.50, y: size.height * 0.37)
        case .side: CGPoint(x: size.width * 0.81, y: size.height * 0.25)
        case .staple: CGPoint(x: size.width * 0.24, y: size.height * 0.70)
        case .soup: CGPoint(x: size.width * 0.76, y: size.height * 0.70)
        }
        let shape = course == .side ? AnyShape(RoundedRectangle(cornerRadius: 16)) : AnyShape(Ellipse())
        let lacquer = scheme == .dark ? Color(red: 0.39, green: 0.20, blue: 0.17) : Color(red: 0.57, green: 0.32, blue: 0.26)
        let showsRiceBowl = recipe?.isPlainRice == true
        return Button {
            if let recipe { open(recipe) } else { add(course) }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    shape.fill(showsRiceBowl ? .clear : (course == .soup ? lacquer : (scheme == .dark ? AppTheme.surface : Color(red: 1, green: 0.98, blue: 0.94))))
                        .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                    if let recipe {
                        RecipeMealImage(height: showsRiceBowl ? dishSize.height : dishSize.height - 12, recipeKey: recipe.key, riceTopDown: true)
                            .frame(width: showsRiceBowl ? dishSize.width : dishSize.width - 12).clipShape(shape)
                            .shadow(color: .black.opacity(showsRiceBowl ? 0.12 : 0), radius: 3, y: 2)
                    } else {
                        shape.stroke(course == .soup ? Color.white.opacity(0.24) : AppTheme.border,
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 4])).padding(7)
                        Image(systemName: allowsAdding ? "plus" : "minus").font(.system(size: 21, weight: .light))
                            .foregroundStyle(course == .soup ? Color.white : AppTheme.accent)
                    }
                    if !showsRiceBowl {
                        shape.stroke(course == .soup ? Color.white.opacity(0.12) : AppTheme.border.opacity(0.45), lineWidth: 0.75)
                    }
                }.frame(width: dishSize.width, height: dishSize.height)
                Text(course.label + (selections.count > 1 ? " · \(selections.count)品" : ""))
                    .font(AppFont.caption.weight(.semibold)).foregroundStyle(AppTheme.text)
            }
        }.buttonStyle(.plain).disabled(recipe == nil && !allowsAdding).frame(width: dishSize.width)
            .contentShape(MealTrayHitShape(dishHeight: dishSize.height, isSide: course == .side))
            .accessibilityLabel(course.label + (recipe.map { "、" + $0.title + "、レシピを見る" } ?? (allowsAdding ? "を選ぶ" : "、記録なし")))
            .accessibilityIdentifier("meal-tray-" + course.rawValue)
            .position(center)
    }
    private func accessibleSlot(_ course: MealCourse) -> some View {
        let selections = selections(for: course)
        return VStack(spacing: 8) {
            Text(course.label).font(AppFont.subheadline.weight(.semibold)).foregroundStyle(AppTheme.text)
            if let meal = selections.first, let recipe = recipes.first(where: { $0.id == meal.recipeID }) {
                Button { open(recipe) } label: {
                    VStack(spacing: 8) {
                        plate(recipe: recipe)
                        Text(recipe.title).font(AppFont.caption.weight(.medium)).foregroundStyle(AppTheme.text)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                }.buttonStyle(.plain).accessibilityLabel(course.label + "、" + recipe.title + "、レシピを見る")
                    .accessibilityIdentifier("meal-tray-" + course.rawValue)
                if allowsAdding { Button { add(course) } label: {
                    Label(selections.count > 1 ? "ほか\(selections.count - 1)品・追加" : "追加", systemImage: "plus")
                        .font(AppFont.caption.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(course.label + "を追加")
                    .accessibilityIdentifier("meal-tray-add-" + course.rawValue) }
            } else {
                Button { add(course) } label: {
                    VStack(spacing: 8) {
                        plate(recipe: nil)
                        Text(allowsAdding ? "選ぶ" : "記録なし").font(AppFont.caption.weight(.semibold)).foregroundStyle(AppTheme.text)
                            .frame(minHeight: 44)
                    }
                }.buttonStyle(.plain).disabled(!allowsAdding).accessibilityLabel(course.label + (allowsAdding ? "を選ぶ" : "、記録なし"))
                    .accessibilityIdentifier("meal-tray-" + course.rawValue)
            }
        }.frame(maxWidth: .infinity)
    }
    private func plate(recipe: Recipe?) -> some View {
        ZStack {
            Circle().fill(recipe?.isPlainRice == true ? .clear : AppTheme.surface).shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            if let recipe {
                RecipeMealImage(height: recipe.isPlainRice ? 120 : 104, recipeKey: recipe.key, riceTopDown: true)
                    .frame(width: recipe.isPlainRice ? 120 : 104).clipShape(Circle())
            } else {
                Circle().strokeBorder(AppTheme.border, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).padding(10)
                Image(systemName: allowsAdding ? "plus" : "minus").font(AppFont.title2.weight(.light)).foregroundStyle(AppTheme.accent)
            }
            if recipe?.isPlainRice != true {
                Circle().strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1)
            }
        }.frame(width: 120, height: 120).accessibilityHidden(true)
    }
}

/// Only the visible dish and its caption receive taps; adjacent plate corners can share bounding boxes.
private struct MealTrayHitShape: Shape {
    let dishHeight: CGFloat
    let isSide: Bool
    func path(in rect: CGRect) -> Path {
        let dish = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(dishHeight, rect.height))
        var path = isSide ? RoundedRectangle(cornerRadius: 16).path(in: dish) : Ellipse().path(in: dish)
        let captionY = dish.maxY + 5
        if captionY < rect.maxY {
            path.addRect(CGRect(x: rect.minX, y: captionY, width: rect.width, height: rect.maxY - captionY))
        }
        return path
    }
}

/// Subtle grain and tapered chopsticks stay vector sharp at every display scale.
private struct TrayWoodGrain: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 1...7 {
            let y = rect.height * CGFloat(row) / 8
            path.move(to: CGPoint(x: 0, y: y))
            path.addCurve(to: CGPoint(x: rect.width, y: y + 3),
                control1: CGPoint(x: rect.width * 0.3, y: y - 6),
                control2: CGPoint(x: rect.width * 0.7, y: y + 6))
        }
        return path
    }
}
private struct TrayChopsticks: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .leading) {
                ForEach([CGFloat(0), CGFloat(6)], id: \.self) { y in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y + 1.5))
                        p.addLine(to: CGPoint(x: w, y: y))
                        p.addLine(to: CGPoint(x: w, y: y + 4))
                        p.addLine(to: CGPoint(x: 0, y: y + 2.5))
                        p.closeSubpath()
                    }.fill(Color(red: 0.33, green: 0.17, blue: 0.10))
                    RoundedRectangle(cornerRadius: 1)
                        .path(in: CGRect(x: w * 0.84, y: y, width: w * 0.12, height: 4))
                        .fill(AppTheme.mealAddFill)
                }
            }
        }.accessibilityHidden(true)
    }
}

struct MealMaterialsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.modelContext) private var context
    let recipes: [Recipe]
    let day: Date
    var isArchive = false
    @Query private var meals: [MealSelection]
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @Query(filter: #Predicate<ShoppingListItem> { !$0.isAddedToInventory }) private var shopping: [ShoppingListItem]
    @State private var weekly = false
    @State private var selectedIDs: Set<String>?
    @State private var now = Date.now
    @State private var completion: String?
    @State private var error: String?
    private var archive: Bool { isArchive || day < MealPlanning.day(now) }
    private var planning: (summary: MealMaterialSummary, visibleIDs: Set<UUID>, plans: [PlannedMeal]) {
        let dates = Set(MealPlanning.days(from: day).prefix(weekly && !archive ? 7 : 1))
        let candidates = meals.filter { $0.isActive || (archive && $0.state == "cooked") }
        let visible = candidates.filter { dates.contains($0.plannedDay(on: now)) }
        let plans = (archive ? visible : candidates).map { meal in
            let ingredients = meal.plannedIngredients(recipes: recipes)
            return PlannedMeal(id: meal.id, day: meal.plannedDay(on: now), createdAt: meal.date,
                ingredients: ingredients ?? [], hasKnownIngredients: ingredients != nil)
        }
        let visibleIDs = Set(visible.map(\.id))
        return (MealPlanning.summarize(plans, visibleIDs: visibleIDs,
            foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
            stock: IngredientIdentity.snapshots(stock, customs: customs, masters: masters), assessAvailability: !archive), visibleIDs, plans)
    }
    private func selection(_ summary: MealMaterialSummary) -> Set<String> {
        if let selectedIDs {
            return selectedIDs.intersection(Set(summary.materials.filter { $0.hasShortage || $0.hasConfirmation }.map(\.id)))
        }
        return Set(summary.materials.filter { $0.hasShortage && !$0.hasConfirmation }.map(\.id))
    }
    private func toggle(_ row: PlannedMaterial, selected: Set<String>) {
        var ids = selected
        if ids.contains(row.id) { ids.remove(row.id) } else { ids.insert(row.id) }
        selectedIDs = ids; completion = nil
    }
    var body: some View {
        let plan = planning
        let materials = plan.summary
        let displayed = materials.displayMaterials
        let coverage = MaterialShoppingCoverage.assess(plans: archive ? [] : plan.plans,
            foods: masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) },
            stock: IngredientIdentity.snapshots(stock, customs: customs, masters: masters),
            purchases: shopping.map(MaterialPurchase.init), visibleMealIDs: plan.visibleIDs)
        let addedIDs = coverage.addedIDs
        let pendingIDs = Set(coverage.remaining.filter { $0.value > 0.0000001 }.map(\.key))
        let selected = selection(materials).intersection(pendingIDs)
        let showAdded = selected.isEmpty && !addedIDs.isEmpty && (completion != nil || pendingIDs.isEmpty)
        List {
            Section {
                Text(weekly && !archive
                    ? MealPlanning.label(day) + "〜" + MealPlanning.label(MealPlanning.days(from: day)[6])
                    : MealPlanning.title(for: day, now: now))
                    .font(AppFont.headline).fixedSize(horizontal: false, vertical: true)
                if !archive {
                    Picker("材料の期間", selection: $weekly) {
                        Text("この日の材料").tag(false); Text("1週間分の材料").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("meal-material-period")
                    if !materials.confirmation.isEmpty {
                        Text("「量を確認」は、選んだものを目安量で追加").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let completion {
                        Text(completion).font(AppFont.caption).foregroundStyle(AppTheme.accent)
                            .accessibilityIdentifier("meal-material-completion")
                            .id("meal-material-feedback")
                    }
                }
            }
            if materials.incomplete {
                Label("取得できない材料があります。レシピを確認してください。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.warning)
            }
            if materials.materials.isEmpty { Text("使用材料はありません") }
            ForEach(displayed) { row in
                if !archive && pendingIDs.contains(row.id) {
                    Button { toggle(row, selected: selected) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: selected.contains(row.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(AppTheme.accent).frame(width: 32, height: 44).accessibilityHidden(true)
                            materialContent(row, added: addedIDs.contains(row.id), partiallyAdded: (coverage.credited[row.id] ?? 0) > 0.0000001)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(description(row, partiallyAdded: (coverage.credited[row.id] ?? 0) > 0.0000001))
                        .accessibilityValue(selected.contains(row.id) ? "選択" : "未選択")
                        .accessibilityIdentifier("meal-material-" + row.key + "-" + row.unit.rawValue)
                } else {
                    materialContent(row, added: addedIDs.contains(row.id), partiallyAdded: (coverage.credited[row.id] ?? 0) > 0.0000001).accessibilityElement(children: .combine)
                        .accessibilityIdentifier("meal-material-" + row.key + "-" + row.unit.rawValue)
                }
            }
            if archive {
                Section { Text("当時の在庫・不足量は記録していません。").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
            }
        }.navigationTitle(archive ? "使用材料" : "使用材料・不足").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(AppTheme.background)
            .modifier(RecipeDateRefresh(date: $now))
            .onChange(of: weekly) { _, _ in selectedIDs = nil; completion = nil }
            .safeAreaInset(edge: .bottom) {
                if !archive {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            do {
                                let count = try MealService(container: context.container).addMaterialShortages(from: day,
                                    days: weekly ? 7 : 1, materialIDs: selected, now: now)
                                completion = count > 0 ? "買い物リストに\(count)品を追加しました。" : "追加する不足分はありません"
                            } catch { self.error = error.localizedDescription }
                        } label: {
                            HStack(spacing: 6) {
                                if showAdded {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success).accessibilityHidden(true)
                                }
                                Text(showAdded ? (completion != nil ? "追加しました" : "追加済み") : "買い物に追加（\(selected.count)品）")
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(CoralPrimaryButtonStyle(fill: AppTheme.mealAddFill))
                            .disabled(selected.isEmpty || materials.incomplete)
                            .accessibilityLabel(showAdded ? (completion != nil ? "追加しました" : "追加済み") : "買い物に追加（\(selected.count)品）")
                            .accessibilityIdentifier("meal-material-add-shopping")
                    }.padding().background(AppTheme.background)
                }
            }
            .alert("買い物に追加できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
    private func description(_ row: PlannedMaterial, partiallyAdded: Bool) -> String {
        [row.name, row.amountLabel, row.hasShortage ? "不足 \(row.shortage.formatted())\(row.unit.label)" : "",
         row.hasConfirmation ? "量を確認 · 目安 \(row.unconfirmed.formatted())\(row.unit.label)" : "",
         partiallyAdded ? "買い物リストに一部追加済み" : ""]
            .filter { !$0.isEmpty }.joined(separator: "、")
    }
    private func materialContent(_ row: PlannedMaterial, added: Bool, partiallyAdded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(row.name).font(AppFont.headline).foregroundStyle(AppTheme.text)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(row.amountLabel).font(AppFont.subheadline).foregroundStyle(AppTheme.secondary)
            }
            if !archive && added {
                Label("買い物リストに追加済み", systemImage: "checkmark.circle.fill")
                    .font(AppFont.caption).foregroundStyle(AppTheme.success)
            } else if !archive && partiallyAdded {
                Text("買い物リストに一部追加済み").font(AppFont.caption).foregroundStyle(AppTheme.secondary)
            }
            if row.optional { Text("お好みで").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
            else if row.mode == "ignored" { Text("在庫管理なし").font(AppFont.caption).foregroundStyle(AppTheme.secondary) }
            else if !archive {
                if row.hasShortage {
                    Label("不足 \(row.shortage.formatted())\(row.unit.label)", systemImage: "basket")
                        .foregroundStyle(AppTheme.danger).font(AppFont.subheadline.weight(.medium))
                }
                if row.hasConfirmation {
                    Label("量を確認 · 目安 \(row.unconfirmed.formatted())\(row.unit.label)", systemImage: "questionmark.circle")
                        .foregroundStyle(AppTheme.warning).font(AppFont.subheadline)
                }
                if !row.hasShortage && !row.hasConfirmation {
                    Label(row.mode == "presence" ? "あり" : "在庫で足ります", systemImage: "checkmark.circle")
                        .foregroundStyle(AppTheme.success).font(AppFont.caption)
                }
            }
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
    }
}
private struct MealRecipePicker: View {
    let recipes: [Recipe]
    let day: Date
    var course: MealCourse? = nil
    @Environment(\.dismiss) private var dismiss
    @Query private var masters: [IngredientMaster]
    @Query private var stock: [InventoryItem]
    @Query private var customs: [CustomIngredient]
    @AppStorage(AppPreferences.defaultServings) private var preferredServings = 1
    @State private var search = ""
    @State private var kind: RecipeKind = .all
    private var choices: [Recipe] {
        recipes.filter { recipe in
            (course.map { MealCourse.of(recipe) == $0 } ?? kind.includes(recipe)) &&
            IngredientSearch.matches(search, names: recipe.isPlainRice ? [recipe.title, "ごはん", "白ごはん", "白米"] : [recipe.title])
        }
    }
    var body: some View {
        let foods = masters.map { RecipeFood(id: $0.id, key: $0.key, name: $0.canonicalName) }
        let snapshots = IngredientIdentity.snapshots(stock, customs: customs, masters: masters)
        let servings = AppPreferences.validatedServings(preferredServings)
        let suggestions = RecipeSuggestions.mealPickerCandidates(choices, foods: foods, stock: snapshots,
            servings: servings, on: day)
        NavigationStack {
            List {
                if course == nil {
                    Section {
                        LabeledFilterMenu(title: "料理の種類", selection: $kind, options: RecipeKind.allCases, label: { $0.label })
                    }
                }
                ForEach(suggestions) { suggestion in
                    NavigationLink { RecipeDetailView(recipe: suggestion.recipe, plannedDate: day, onAdded: { dismiss() }) } label: {
                        HStack(spacing: 12) {
                            RecipeMealImage(height: 48, recipeKey: suggestion.recipe.key).frame(width: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.recipe.title).font(AppFont.headline)
                                SuggestionSummaryView(suggestion: suggestion, compact: true,
                                    identifier: "plan-candidate-" + suggestion.recipe.key)
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("plan-recipe-" + suggestion.recipe.key)
                }
            }.searchable(text: $search, prompt: "料理名で検索")
                .scrollContentBackground(.hidden).background(AppTheme.background)
                .navigationTitle(course.map { $0.label + "を選ぶ" } ?? "料理を追加").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.accessibilityIdentifier("meal-picker-close") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text(MealPlanning.label(day)).font(AppFont.caption).foregroundStyle(AppTheme.secondary)
                            .lineLimit(1).accessibilityIdentifier("meal-picker-date")
                    }
                }
        }
    }
}
