import SwiftUI

/// Rapport « Flux de trésorerie » : diagramme reliant les sources de revenus aux postes de
/// dépenses et à l'épargne. Suit la période et le compte de la barre d'outils.
struct MoneyFlowChartView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var transactionsController: TransactionsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var booksController: BooksController
    @EnvironmentObject var appSettings: AppSettings

    private static let maxSources = 4
    private static let maxPosts = 7

    struct Node: Identifiable {
        let id: String
        let name: String
        let amount: Decimal
        let color: Color

        var doubleAmount: Double { NSDecimalNumber(decimal: amount).doubleValue }
    }

    struct FlowData {
        var sources: [Node] = []
        var posts: [Node] = []
        var income: Decimal = 0
        var expense: Decimal = 0

        /// Hauteur totale du diagramme : le plus grand des deux côtés
        var total: Decimal { max(income, expense) }
        var saving: Decimal { income - expense }
    }

    var body: some View {
        let data = self.data

        if data.total == 0 {
            ReportEmptyState(systemImage: "arrow.triangle.branch")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: NativeMetrics.groupSpacing) {
                    tiles(data)
                    diagramBlock(data)
                    tableBlock(data)
                }
            }
        }
    }

    // MARK: - Chiffres clés

    private func tiles(_ data: FlowData) -> some View {
        let firstPost = data.posts.first { $0.id != "saving" }

        return ReportTiles {
            StatTile(title: "Revenus", value: money(data.income), valueColor: .green, detail: countText(data.sources.filter { $0.id != "deficit" }.count, "source"))
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(title: "Dépenses", value: money(data.expense), detail: share(data.expense, of: data.income).map { "\($0) des revenus" })
                .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: data.saving >= 0 ? "Épargne" : "Déficit",
                value: money(abs(data.saving)),
                valueColor: data.saving >= 0 ? .green : .red,
                detail: share(abs(data.saving), of: data.income).map { "\($0) des revenus" }
            )
            .privacyBlur(hidden: appSettings.hideAmounts)

            StatTile(
                title: "Premier poste",
                value: firstPost?.name ?? "—",
                detail: firstPost.flatMap { share($0.amount, of: data.total) }.map { "\($0) du total" }
            )
        }
    }

    // MARK: - Diagramme

    private func diagramBlock(_ data: FlowData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupTitle("D'où vient l'argent, où il part")

            FlowDiagram(
                sources: data.sources,
                posts: data.posts,
                total: NSDecimalNumber(decimal: data.total).doubleValue,
                label: { node in "\(node.name)  \(appSettings.hideAmounts ? "•••" : money(node.amount))" }
            )
            .frame(height: max(320, CGFloat(max(data.sources.count, data.posts.count)) * 46))
        }
        .padding(NativeMetrics.groupPadding)
        .cardBackground()
    }

    // MARK: - Tableau

    private func tableBlock(_ data: FlowData) -> some View {
        ReportTable(
            columns: ["Poste", "Sens", "Montant", "Part du total"],
            rows: (data.sources + data.posts).map { node in
                let isSource = data.sources.contains { $0.id == node.id }
                return ReportRow(id: (isSource ? "in-" : "out-") + node.id, cells: [
                    ReportCell(text: node.name),
                    ReportCell(text: isSource ? "Entrée" : "Sortie", color: .secondary, isAmount: false),
                    ReportCell(text: money(node.amount)),
                    ReportCell(text: share(node.amount, of: data.total) ?? "—", color: .secondary)
                ])
            },
            footnote: "Les transferts entre comptes sont exclus. Quand les dépenses dépassent les revenus, l'écart apparaît à gauche comme « Puisé dans l'épargne »."
        )
    }

    // MARK: - Données

    private var data: FlowData {
        let transactions = transactionsController.filteredTransactions.filter {
            $0.type != .transfer && $0.status != .skipped
                && accountsController.isReported($0, accountFilter: transactionsController.filters.accountID)
        }

        func posts(of type: TransactionType, limit: Int, othersName: String) -> [ReportPost] {
            var names: [String: String] = [:]
            var totals: [String: Decimal] = [:]
            for transaction in transactions where transaction.type == type {
                let root = categoriesController.topLevelCategory(of: transaction.categoryID)
                let key = root?.id.uuidString ?? ReportPost.uncategorizedID
                names[key] = root?.name ?? "Sans catégorie"
                totals[key, default: 0] += abs(transaction.amount)
            }
            return totals
                .map { ReportPost(id: $0.key, name: names[$0.key] ?? "—", amount: $0.value) }
                .grouped(limit: limit, othersName: othersName)
        }

        let incomePosts = posts(of: .credit, limit: Self.maxSources, othersName: "Autres revenus")
        let expensePosts = posts(of: .debit, limit: Self.maxPosts, othersName: "Autres dépenses")
        let income = incomePosts.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = expensePosts.reduce(Decimal(0)) { $0 + $1.amount }

        let incomeColors: [Color] = [.green, .teal, .mint, .cyan, .gray]
        var sources = incomePosts.enumerated().map { index, post in
            Node(id: post.id, name: post.name, amount: post.amount, color: incomeColors[index % incomeColors.count])
        }
        var targets = expensePosts.enumerated().map { index, post in
            Node(id: post.id, name: post.name, amount: post.amount,
                 color: post.id == ReportPost.othersID ? .gray : ReportPalette.color(at: index))
        }

        if income > expense {
            targets.append(Node(id: "saving", name: "Épargne", amount: income - expense, color: .green))
        } else if expense > income {
            sources.append(Node(id: "deficit", name: "Puisé dans l'épargne", amount: expense - income, color: .red))
        }

        return FlowData(sources: sources, posts: targets, income: income, expense: expense)
    }

    // MARK: - Format

    private var currency: String {
        booksController.currentBook?.currency ?? "EUR"
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    private func share(_ amount: Decimal, of total: Decimal) -> String? {
        guard total > 0 else { return nil }
        return NSDecimalNumber(decimal: amount / total).doubleValue.formatted(.percent.precision(.fractionLength(0)))
    }

    private func countText(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count > 1 ? "s" : "")"
    }
}

// MARK: - Dessin du diagramme

/// Diagramme de flux à trois colonnes : sources à gauche, tronc central, postes à droite.
/// La hauteur de chaque bande est proportionnelle à son montant. Les libellés sont écartés
/// les uns des autres quand les bandes sont fines, et raccourcis quand la place manque.
private struct FlowDiagram: View {
    let sources: [MoneyFlowChartView.Node]
    let posts: [MoneyFlowChartView.Node]
    let total: Double
    let label: (MoneyFlowChartView.Node) -> String

    private let maxLabelWidth: CGFloat = 190
    private let barWidth: CGFloat = 10
    private let gap: CGFloat = 8
    /// Écart vertical minimal entre deux libellés d'une même colonne
    private let lineSpacing: CGFloat = 18
    /// Espace entre une barre et son libellé
    private let labelInset: CGFloat = 8

    private struct LabelRequest {
        let node: MoneyFlowChartView.Node
        /// Milieu vertical de la barre du poste
        let anchorY: CGFloat
        var y: CGFloat
    }

    var body: some View {
        Canvas { context, size in
            guard total > 0, size.width > 260 else { return }

            // Colonnes de libellés : la place nécessaire, sans dépasser 190 points ni un tiers de la largeur
            let available = (size.width - 120) / 2
            let widest = (sources + posts).map { resolved(label($0), in: context).measure(in: size).width }.max() ?? 0
            let labelWidth = min(maxLabelWidth, available, widest + labelInset + 4)

            let leftX = labelWidth
            let rightX = size.width - labelWidth - barWidth
            let midX = (leftX + rightX) / 2
            let count = CGFloat(max(sources.count, posts.count))
            // Hauteur utile du tronc : ce qui reste une fois les espacements du côté le plus fourni retirés
            let trunkHeight = max(40, size.height - gap * (count - 1))
            let scale = trunkHeight / total
            let trunkTop = (size.height - trunkHeight) / 2

            // Tronc central
            let trunk = CGRect(x: midX, y: trunkTop, width: barWidth, height: trunkHeight)
            context.fill(Path(roundedRect: trunk, cornerRadius: 2), with: .color(.secondary.opacity(0.6)))

            let left = draw(sources, in: &context, size: size, nodeX: leftX, trunkX: midX, trunkTop: trunkTop, scale: scale, isSource: true)
            let right = draw(posts, in: &context, size: size, nodeX: rightX, trunkX: midX + barWidth, trunkTop: trunkTop, scale: scale, isSource: false)

            drawLabels(left, in: &context, size: size, barEdge: leftX, width: labelWidth - labelInset, isSource: true)
            drawLabels(right, in: &context, size: size, barEdge: rightX + barWidth, width: labelWidth - labelInset, isSource: false)
        }
        .accessibilityLabel("Diagramme des flux, détaillé dans le tableau ci-dessous")
    }

    /// Barres et bandes d'une colonne ; renvoie l'emplacement souhaité de chaque libellé
    private func draw(
        _ nodes: [MoneyFlowChartView.Node],
        in context: inout GraphicsContext,
        size: CGSize,
        nodeX: CGFloat,
        trunkX: CGFloat,
        trunkTop: CGFloat,
        scale: CGFloat,
        isSource: Bool
    ) -> [LabelRequest] {
        let heights = nodes.map { max(CGFloat($0.doubleAmount) * scale, 1) }
        let stackHeight = heights.reduce(0, +) + gap * CGFloat(max(nodes.count - 1, 0))
        var nodeY = (size.height - stackHeight) / 2
        var trunkY = trunkTop
        var requests: [LabelRequest] = []

        for (node, height) in zip(nodes, heights) {
            // Barre du poste
            let bar = CGRect(x: nodeX, y: nodeY, width: barWidth, height: height)
            context.fill(Path(roundedRect: bar, cornerRadius: 2), with: .color(node.color))

            // Bande reliant le poste au tronc
            let startX = isSource ? nodeX + barWidth : trunkX
            let endX = isSource ? trunkX : nodeX
            let startY = isSource ? nodeY : trunkY
            let endY = isSource ? trunkY : nodeY
            let controlX = (startX + endX) / 2

            var band = Path()
            band.move(to: CGPoint(x: startX, y: startY))
            band.addCurve(
                to: CGPoint(x: endX, y: endY),
                control1: CGPoint(x: controlX, y: startY),
                control2: CGPoint(x: controlX, y: endY)
            )
            band.addLine(to: CGPoint(x: endX, y: endY + height))
            band.addCurve(
                to: CGPoint(x: startX, y: startY + height),
                control1: CGPoint(x: controlX, y: endY + height),
                control2: CGPoint(x: controlX, y: startY + height)
            )
            band.closeSubpath()
            context.fill(band, with: .color(node.color.opacity(0.28)))

            let center = nodeY + height / 2
            requests.append(LabelRequest(node: node, anchorY: center, y: center))

            nodeY += height + gap
            trunkY += height
        }
        return requests
    }

    /// Libellés d'une colonne, espacés d'au moins `lineSpacing`, reliés à leur barre s'ils ont dû être décalés
    private func drawLabels(
        _ requests: [LabelRequest],
        in context: inout GraphicsContext,
        size: CGSize,
        barEdge: CGFloat,
        width: CGFloat,
        isSource: Bool
    ) {
        guard !requests.isEmpty else { return }
        var placed = requests
        let top = lineSpacing / 2
        let bottom = size.height - lineSpacing / 2

        // Descente : chaque libellé sous le précédent, puis remontée si le dernier déborde en bas
        for index in placed.indices {
            let minimum = index == 0 ? top : placed[index - 1].y + lineSpacing
            placed[index].y = max(placed[index].y, minimum)
        }
        for index in placed.indices.reversed() {
            let maximum = index == placed.count - 1 ? bottom : placed[index + 1].y - lineSpacing
            placed[index].y = min(placed[index].y, maximum)
        }

        for request in placed {
            let textX = isSource ? barEdge - labelInset : barEdge + labelInset
            // Trait de rappel quand le libellé n'est plus en face de sa barre
            if abs(request.y - request.anchorY) > 3 {
                var leader = Path()
                leader.move(to: CGPoint(x: barEdge, y: request.anchorY))
                leader.addLine(to: CGPoint(x: isSource ? textX + 3 : textX - 3, y: request.y))
                context.stroke(leader, with: .color(.secondary.opacity(0.5)), lineWidth: 0.75)
            }
            let text = fitted(request.node, width: width, in: context)
            context.draw(text, at: CGPoint(x: textX, y: request.y), anchor: isSource ? .trailing : .leading)
        }
    }

    // MARK: - Texte

    private func resolved(_ string: String, in context: GraphicsContext) -> GraphicsContext.ResolvedText {
        context.resolve(Text(string).font(.callout).foregroundStyle(.primary))
    }

    /// Libellé complet s'il tient ; sinon le nom seul, puis le nom abrégé avec « … »
    private func fitted(_ node: MoneyFlowChartView.Node, width: CGFloat, in context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: lineSpacing)
        let full = resolved(label(node), in: context)
        if full.measure(in: unbounded).width <= width { return full }

        var name = node.name
        var candidate = resolved(name, in: context)
        while candidate.measure(in: unbounded).width > width, name.count > 1 {
            name.removeLast()
            candidate = resolved(name.trimmingCharacters(in: .whitespaces) + "…", in: context)
        }
        return candidate
    }
}
