import SwiftUI

struct ScrollRepresentable<Content: View, ScrollItem>: UIViewControllerRepresentable where ScrollItem : Identifiable, ScrollItem: Hashable {

    let scrollView: EndlessScrollView<ScrollItem>
    let content: (Int, ScrollItem) -> Content

    func makeUIViewController(context: Context) -> ScrollController {
        ScrollController.init(scrollView: scrollView, content: content)
    }

    func updateUIViewController(_ controller: ScrollController, context: Context) {}

    class ScrollController: UIViewController {
        let scrollView: EndlessScrollView<ScrollItem>
        fileprivate var items: [ScrollItem] = []
        fileprivate var content: ((Int, ScrollItem) -> Content)!

        fileprivate init(scrollView: EndlessScrollView<ScrollItem>, content: @escaping (Int, ScrollItem) -> Content) {
            self.scrollView = scrollView
            self.content = content
            super.init(nibName: nil, bundle: nil)
            self.view = scrollView
            scrollView.createCell = createCell
            scrollView.updateCell = updateCell
        }

        required init?(coder: NSCoder) { fatalError() }

        private func createCell(_ index: Int, _ items: [ScrollItem], _ cellsToReuse: inout [UIView]) -> UIView {
            let item: ScrollItem? = index >= 0 && index < items.count ? items[index] : nil
            let cell: UIView
            if #available(iOS 16.0, *), false {
                let c: UITableViewCell = cellsToReuse.isEmpty ? UITableViewCell() : cellsToReuse.removeLast() as! UITableViewCell
                if let item {
                    c.contentConfiguration = UIHostingConfiguration { self.content(index, item) }
                        .margins(.all, 0)
                        .minSize(height: 1)
                }
                cell = c
            } else {
                let c = cellsToReuse.isEmpty ? HostingCell<Content>() : cellsToReuse.removeLast() as! HostingCell<Content>
                if let item {
                    c.set(content: self.content(index, item), parent: self)
                }
                cell = c
            }
            cell.isHidden = false
            cell.backgroundColor = .clear
            let size = cell.systemLayoutSizeFitting(CGSizeMake(scrollView.bounds.width, CGFloat.greatestFiniteMagnitude))
            cell.frame.size.width = scrollView.bounds.width
            cell.frame.size.height = size.height
            return cell
        }

        private func updateCell(cell: UIView, _ index: Int, _ items: [ScrollItem]) {
            let item = items[index]
            if #available(iOS 16.0, *), false {
                (cell as! UITableViewCell).contentConfiguration = UIHostingConfiguration { self.content(index, item) }
                    .margins(.all, 0)
                    .minSize(height: 1)
            } else {
                if let cell = cell as? HostingCell<Content> {
                    cell.set(content: self.content(index, item), parent: self)
                } else {
                    fatalError("Unexpected Cell Type for: \(item)")
                }
            }
            let size = cell.systemLayoutSizeFitting(CGSizeMake(scrollView.bounds.width, CGFloat.greatestFiniteMagnitude))
            cell.frame.size.width = scrollView.bounds.width
            cell.frame.size.height = size.height
            cell.setNeedsLayout()
        }
    }
}

class EndlessScrollView<ScrollItem>: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate where ScrollItem : Identifiable, ScrollItem: Hashable {

    let listState: ListState = ListState()

    var initialOffset: CGFloat = 100000000

    fileprivate static var DEFAULT_ITEM_ID: any Hashable { get { Int64.min } }

    var prevProcessedOffset: CGFloat = 0

    var oldScreenHeight: CGFloat = 0

    var estimatedContentHeight: ContentHeight = ContentHeight()

    var averageItemHeight: CGFloat = 30

    var scrollStepMultiplier: CGFloat = 0.37

    var insetTop: CGFloat = 100

    var insetBottom: CGFloat = 100

    var scrollToItemIndexDelayed: Int? = nil

    let scrollBarView: UIScrollView = UIScrollView(frame: .zero)

    var cellsToReuse: [UIView] = []

    var debug: Bool = false

    var createCell: (Int, [ScrollItem], inout [UIView]) -> UIView? = { _, _, _ in nil }
    var updateCell: (UIView, Int, [ScrollItem]) -> Void = { cell, _, _ in }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    class ListState: NSObject {

        var onUpdateListener: () -> Void = {}

        var items: [ScrollItem] = [] {
            didSet {
                onUpdateListener()
            }
        }

        var totalItemsCount: Int {
            items.count
        }

        var visibleItems: [EndlessScrollView<ScrollItem>.VisibleItem] = []

        var firstVisibleItemIndex: Int = 0

        var firstVisibleItemId: any Hashable = EndlessScrollView<ScrollItem>.DEFAULT_ITEM_ID

        var firstVisibleItemOffset: CGFloat = -100

        var lastVisibleItemIndex: Int {
            visibleItems.last?.index ?? 0
        }

        var itemsCanCoverScreen: Bool = false

        var isScrolling: Bool = false
        var isAnimatedScrolling: Bool = false

        override init() {
            super.init()
        }
    }

    class VisibleItem {
        let index: Int
        let item: ScrollItem
        let view: UIView
        var offset: CGFloat

        init(index: Int, item: ScrollItem, view: UIView, offset: CGFloat) {
            self.index = index
            self.item = item
            self.view = view
            self.offset = offset
        }
    }

    class ContentHeight {
        var topOffsetY: CGFloat = 0
        var bottomOffsetY: CGFloat = 0

        var virtualScrollOffsetY: CGFloat = 0

        var overscrolledTop: CGFloat = 0

        var inset: CGFloat = 100

        var height: CGFloat {
            get { bottomOffsetY - topOffsetY }
        }

        var virtualOverscrolledHeight: CGFloat {
            get {
                bottomOffsetY - topOffsetY + overscrolledTop - inset * 2
            }
        }

        func update(
            _ contentOffset: CGPoint,
            _ listState: ListState,
            _ averageItemHeight: CGFloat,
            _ updateStaleHeight: Bool
        ) {
            let lastVisible = listState.visibleItems.last
            let firstVisible = listState.visibleItems.first
            guard let last = lastVisible, let first = firstVisible else {
                topOffsetY = contentOffset.y
                bottomOffsetY = contentOffset.y
                virtualScrollOffsetY = 0
                overscrolledTop = 0
                return
            }
            topOffsetY = last.view.frame.origin.y - CGFloat(listState.totalItemsCount - last.index - 1) * averageItemHeight - self.inset
            bottomOffsetY = first.view.frame.origin.y + first.view.bounds.height + CGFloat(first.index) * averageItemHeight + self.inset
            virtualScrollOffsetY = contentOffset.y - topOffsetY
            overscrolledTop = max(0, last.index == listState.totalItemsCount - 1 ? last.view.frame.origin.y - contentOffset.y : 0)
        }
    }

    var topY: CGFloat {
        get { contentOffset.y }
    }

    var bottomY: CGFloat {
        get { contentOffset.y + bounds.height }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if contentSize.height == 0 {
            setup()
        }
        let newScreenHeight = bounds.height
        if newScreenHeight != oldScreenHeight && oldScreenHeight != 0 {
            contentOffset.y += oldScreenHeight - newScreenHeight
            scrollBarView.frame = CGRectMake(frame.width - 10, self.insetTop, 10, frame.height - self.insetTop - self.insetBottom)
        }
        oldScreenHeight = newScreenHeight
        adaptItems(listState.items, false)
        if let index = scrollToItemIndexDelayed {
            scrollToItem(index)
            scrollToItemIndexDelayed = nil
        }
    }

    private func setup() {
        contentSize = CGSizeMake(frame.size.width, initialOffset * 2)
        prevProcessedOffset = initialOffset
        contentOffset = CGPointMake(0, initialOffset)

        showsVerticalScrollIndicator = false
        scrollBarView.showsHorizontalScrollIndicator = false
        panGestureRecognizer.delegate = self
        addGestureRecognizer(scrollBarView.panGestureRecognizer)
        superview!.addSubview(scrollBarView)
    }

    func updateItems(_ items: [ScrollItem], _ forceReloadVisible: Bool = false) {
        if !Thread.isMainThread {
            logger.error("Use main thread to update items")
            return
        }
        if bounds.height == 0 {
            self.listState.items = items
            return
        }
        adaptItems(items, forceReloadVisible)
        snapToContent(animated: false)
    }

    private func adaptItems(_ items: [ScrollItem], _ forceReloadVisible: Bool, overridenOffset: CGFloat? = nil) {
        let start = Date.now
        if items.isEmpty {
            listState.visibleItems.forEach { item in item.view.removeFromSuperview() }
            listState.visibleItems = []
            listState.itemsCanCoverScreen = false
            listState.firstVisibleItemId = EndlessScrollView<ScrollItem>.DEFAULT_ITEM_ID
            listState.firstVisibleItemIndex = 0
            listState.firstVisibleItemOffset = -insetTop

            estimatedContentHeight.update(contentOffset, listState, averageItemHeight, true)
            scrollBarView.contentSize = .zero
            scrollBarView.contentOffset = .zero

            prevProcessedOffset = contentOffset.y
            if !self.listState.items.isEmpty {
                self.listState.items = items
            }
            return
        }

        let contentOffsetY = overridenOffset ?? contentOffset.y

        var oldVisible = listState.visibleItems
        var newVisible: [VisibleItem] = []
        var visibleItemsHeight: CGFloat = 0
        let offsetsDiff = contentOffsetY - prevProcessedOffset

        var shouldBeFirstVisible = items.firstIndex(where: { item in item.id == listState.firstVisibleItemId as! ScrollItem.ID }) ?? 0

        var wasFirstVisibleItemOffset = listState.firstVisibleItemOffset
        var alreadyChangedIndexWhileScrolling = false
        var allowOneMore = false
        var nextOffsetY: CGFloat = 0
        var i = shouldBeFirstVisible
        while i >= 0 && i < items.count {
            let item = items[i]
            let visibleIndex = oldVisible.firstIndex(where: { vis in vis.item.id == item.id })
            let visible: VisibleItem?
            if let visibleIndex {
                let v = oldVisible.remove(at: visibleIndex)
                if forceReloadVisible || v.view.bounds.width != bounds.width || v.item.hashValue != item.hashValue {
                    let wasHeight = v.view.bounds.height
                    updateCell(v.view, i, items)
                    if wasHeight < v.view.bounds.height && i == 0 && shouldBeFirstVisible == i {
                        v.view.frame.origin.y -= v.view.bounds.height - wasHeight
                    }
                }
                visible = v
            } else {
                visible = nil
            }
            if shouldBeFirstVisible == i {
                if let vis = visible {

                    if
                        (listState.isAnimatedScrolling && vis.view.frame.origin.y + vis.view.bounds.height < contentOffsetY + bounds.height) ||
                        !isVisible(vis.view) {
                        let newIndex: Int
                        if listState.isAnimatedScrolling {
                            var indexDiff = !alreadyChangedIndexWhileScrolling ? Int(ceil(abs(offsetsDiff / averageItemHeight))) : 0
                            alreadyChangedIndexWhileScrolling = true

                            indexDiff = offsetsDiff <= 0 ? indexDiff : -indexDiff
                            newIndex = max(0, min(items.count - 1, i + indexDiff))
                            wasFirstVisibleItemOffset = 0
                        } else {
                            newIndex = i + (offsetsDiff <= 0 ? 1 : -1)
                        }
                        shouldBeFirstVisible = newIndex
                        i = newIndex

                        cellsToReuse.append(vis.view)
                        hideAndRemoveFromSuperviewIfNeeded(vis.view)
                        continue
                    }
                }
                let vis: VisibleItem
                if let visible {
                    vis = VisibleItem(index: i, item: item, view: visible.view, offset: offsetToBottom(visible.view))
                } else {
                    let cell = createCell(i, items, &cellsToReuse)!
                    cell.frame.origin.y = bottomY + wasFirstVisibleItemOffset - cell.frame.height
                    vis = VisibleItem(index: i, item: item, view: cell, offset: offsetToBottom(cell))
                }
                if vis.view.superview == nil {
                    addSubview(vis.view)
                }
                newVisible.append(vis)
                visibleItemsHeight += vis.view.frame.height
                nextOffsetY = vis.view.frame.origin.y
            } else {
                let vis: VisibleItem
                if let visible {
                    vis = VisibleItem(index: i, item: item, view: visible.view, offset: offsetToBottom(visible.view))
                    nextOffsetY -= vis.view.frame.height
                    vis.view.frame.origin.y = nextOffsetY
                } else {
                    let cell = createCell(i, items, &cellsToReuse)!
                    nextOffsetY -= cell.frame.height
                    cell.frame.origin.y = nextOffsetY
                    vis = VisibleItem(index: i, item: item, view: cell, offset: offsetToBottom(cell))
                }
                if vis.view.superview == nil {
                    addSubview(vis.view)
                }
                newVisible.append(vis)
                visibleItemsHeight += vis.view.frame.height
            }
            if abs(nextOffsetY) < contentOffsetY && !allowOneMore {
                break
            } else if abs(nextOffsetY) < contentOffsetY {
                allowOneMore = false
            }
            i += 1
        }
        if let firstVisible = newVisible.first, firstVisible.view.frame.origin.y + firstVisible.view.frame.height < contentOffsetY + bounds.height, firstVisible.index > 0 {
            var offset: CGFloat = firstVisible.view.frame.origin.y + firstVisible.view.frame.height
            let index = firstVisible.index
            for i in stride(from: index - 1, through: 0, by: -1) {
                let item = items[i]
                let visibleIndex = oldVisible.firstIndex(where: { vis in vis.item.id == item.id })
                let vis: VisibleItem
                if let visibleIndex {
                    let visible = oldVisible.remove(at: visibleIndex)
                    visible.view.frame.origin.y = offset
                    vis = VisibleItem(index: i, item: item, view: visible.view, offset: offsetToBottom(visible.view))
                } else {
                    let cell = createCell(i, items, &cellsToReuse)!
                    cell.frame.origin.y = offset
                    vis = VisibleItem(index: i, item: item, view: cell, offset: offsetToBottom(cell))
                }
                if vis.view.superview == nil {
                    addSubview(vis.view)
                }
                offset += vis.view.frame.height
                newVisible.insert(vis, at: 0)
                visibleItemsHeight += vis.view.frame.height
                if offset >= contentOffsetY + bounds.height {
                    break
                }
            }
        }

        oldVisible.forEach { vis in
            cellsToReuse.append(vis.view)
            hideAndRemoveFromSuperviewIfNeeded(vis.view)
        }
        let itemsCountChanged = listState.items.count != items.count
        prevProcessedOffset = contentOffsetY

        listState.visibleItems = newVisible
        listState.itemsCanCoverScreen = visibleItemsHeight >= bounds.height - insetTop

        listState.firstVisibleItemId = listState.visibleItems.first?.item.id ?? EndlessScrollView<ScrollItem>.DEFAULT_ITEM_ID
        listState.firstVisibleItemIndex = listState.visibleItems.first?.index ?? 0
        listState.firstVisibleItemOffset = listState.visibleItems.first?.offset ?? -insetTop
        listState.items = items

        estimatedContentHeight.update(contentOffset, listState, averageItemHeight, itemsCountChanged)
        scrollBarView.contentSize = CGSizeMake(bounds.width, estimatedContentHeight.virtualOverscrolledHeight)
        scrollBarView.contentOffset = CGPointMake(0, estimatedContentHeight.virtualScrollOffsetY)
        scrollBarView.isHidden = listState.visibleItems.count == listState.items.count && (listState.visibleItems.isEmpty || -listState.firstVisibleItemOffset + (listState.visibleItems.last?.offset ?? 0) + insetTop < bounds.height)

        if debug {
            println("time spent \((-start.timeIntervalSinceNow).description.prefix(5).replacingOccurrences(of: "0.000", with: "<0").replacingOccurrences(of: "0.", with: ""))")
        }
    }

    func setScrollPosition(_ index: Int, _ id: Int64, _ offset: CGFloat = 0) {
        listState.firstVisibleItemIndex = index
        listState.firstVisibleItemId = id
        listState.firstVisibleItemOffset = offset == 0 ? -bounds.height + insetTop + insetBottom : offset
    }

    func scrollToItem(_ index: Int, top: Bool = true) {
        if index >= listState.items.count || listState.isScrolling || listState.isAnimatedScrolling {
            return
        }
        if bounds.height == 0 || contentSize.height == 0 {
            scrollToItemIndexDelayed = index
            return
        }
        listState.isScrolling = true
        defer {
            listState.isScrolling = false
        }

        listState.firstVisibleItemIndex = index
        listState.firstVisibleItemId = listState.items[index].id
        listState.firstVisibleItemOffset = -bounds.height + insetTop + insetBottom
        scrollBarView.flashScrollIndicators()
        adaptItems(listState.items, false)

        var adjustedOffset = self.contentOffset.y
        var i = 0

        var upPrev = index > listState.firstVisibleItemIndex

        var stepSlowdownMultiplier: CGFloat = 1
        while i < 200 {
            let up = index > listState.firstVisibleItemIndex
            if upPrev != up {
                stepSlowdownMultiplier = stepSlowdownMultiplier * 0.5
                upPrev = up
            }

            let firstOrLastIndex = up ? listState.visibleItems.last?.index ?? 0 : listState.firstVisibleItemIndex
            let step: CGFloat = max(0.1, CGFloat(abs(index - firstOrLastIndex)) * scrollStepMultiplier) * stepSlowdownMultiplier

            let offsetToScroll = (up ? -averageItemHeight : averageItemHeight) * step
            adjustedOffset += offsetToScroll
            if let item = listState.visibleItems.first(where: { $0.index == index }) {
                let y = if top {
                    min(estimatedContentHeight.bottomOffsetY - bounds.height, item.view.frame.origin.y - insetTop)
                } else {
                    max(estimatedContentHeight.topOffsetY - insetTop - insetBottom, item.view.frame.origin.y + item.view.bounds.height - bounds.height + insetBottom)
                }
                setContentOffset(CGPointMake(contentOffset.x, y), animated: false)
                scrollBarView.flashScrollIndicators()
                break
            }
            contentOffset = CGPointMake(contentOffset.x, adjustedOffset)
            adaptItems(listState.items, false)
            snapToContent(animated: false)
            i += 1
        }
        adaptItems(listState.items, false)
        snapToContent(animated: false)
        estimatedContentHeight.update(contentOffset, listState, averageItemHeight, true)
    }

    func scrollToItemAnimated(_ index: Int, top: Bool = true) async {
        if index >= listState.items.count || listState.isScrolling || listState.isAnimatedScrolling {
            return
        }
        listState.isAnimatedScrolling = true
        defer {
            listState.isAnimatedScrolling = false
        }
        var adjustedOffset = self.contentOffset.y
        var i = 0

        var upPrev = index > listState.firstVisibleItemIndex

        var stepSlowdownMultiplier: CGFloat = 1
        while i < 200 {
            let up = index > listState.firstVisibleItemIndex
            if upPrev != up {
                stepSlowdownMultiplier = stepSlowdownMultiplier * 0.5
                upPrev = up
            }

            let firstOrLastIndex = up ? listState.visibleItems.last?.index ?? 0 : listState.firstVisibleItemIndex
            let step: CGFloat = max(0.1, CGFloat(abs(index - firstOrLastIndex)) * scrollStepMultiplier) * stepSlowdownMultiplier

            let offsetToScroll = (up ? -averageItemHeight : averageItemHeight) * step
            adjustedOffset += offsetToScroll
            if let item = listState.visibleItems.first(where: { $0.index == index }) {
                let y = if top {
                    min(estimatedContentHeight.bottomOffsetY - bounds.height, item.view.frame.origin.y - insetTop)
                } else {
                    max(estimatedContentHeight.topOffsetY - insetTop - insetBottom, item.view.frame.origin.y + item.view.bounds.height - bounds.height + insetBottom)
                }
                setContentOffset(CGPointMake(contentOffset.x, y), animated: true)
                scrollBarView.flashScrollIndicators()
                break
            }
            contentOffset = CGPointMake(contentOffset.x, adjustedOffset)

            if prevProcessedOffset - contentOffset.y != 0 {
                adaptItems(listState.items, false)
                snapToContent(animated: false)
            }
            await MainActor.run {}

            i += 1
        }
        estimatedContentHeight.update(contentOffset, listState, averageItemHeight, true)
    }

    func scrollToBottom() {
        scrollToItem(0, top: false)
    }

    func scrollToBottomAnimated() {
        Task {
            await scrollToItemAnimated(0, top: false)
        }
    }

    func scroll(by: CGFloat, animated: Bool = true) {
        setContentOffset(CGPointMake(contentOffset.x, contentOffset.y + by), animated: animated)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        if !listState.items.isEmpty {
            scrollToBottomAnimated()
        }
        return false
    }

    private func snapToContent(animated: Bool) {
        let topBlankSpace = estimatedContentHeight.height < bounds.height ? bounds.height - estimatedContentHeight.height : 0
        if topY < estimatedContentHeight.topOffsetY - topBlankSpace {
            setContentOffset(CGPointMake(0, estimatedContentHeight.topOffsetY - topBlankSpace), animated: animated)
        } else if bottomY > estimatedContentHeight.bottomOffsetY {
            setContentOffset(CGPointMake(0, estimatedContentHeight.bottomOffsetY - bounds.height), animated: animated)
        }
    }

    func offsetToBottom(_ view: UIView) -> CGFloat {
        bottomY - (view.frame.origin.y + view.frame.height)
    }

    func hideAndRemoveFromSuperviewIfNeeded(_ view: UIView) {
        if view.isHidden {
            return
        }
        (view as? ReusableView)?.prepareForReuse()
        view.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if view.isHidden { view.removeFromSuperview() }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            snapToContent(animated: true)
        }
    }

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            var newOffset = newValue
            let topBlankSpace = estimatedContentHeight.height < bounds.height ? bounds.height - estimatedContentHeight.height : 0
            if contentOffset.y > 0 && newOffset.y < estimatedContentHeight.topOffsetY - topBlankSpace && contentOffset.y > newOffset.y {
                if !isDecelerating {
                    newOffset.y = min(contentOffset.y, newOffset.y + abs(newOffset.y - estimatedContentHeight.topOffsetY + topBlankSpace) / 1.8)
                } else {
                    DispatchQueue.main.async {
                        self.setContentOffset(newValue, animated: false)
                        self.snapToContent(animated: true)
                    }
                }
            } else if contentOffset.y > 0 && newOffset.y + bounds.height > estimatedContentHeight.bottomOffsetY && contentOffset.y < newOffset.y {
                if !isDecelerating {
                    newOffset.y = max(contentOffset.y, newOffset.y - abs(newOffset.y + bounds.height - estimatedContentHeight.bottomOffsetY) / 1.8)
                } else {
                    DispatchQueue.main.async {
                        self.setContentOffset(newValue, animated: false)
                        self.snapToContent(animated: true)
                    }
                }
            }
            super.contentOffset = newOffset
        }
    }

    private func stopScrolling() {
        let offsetYToStopAt = if abs(contentOffset.y - estimatedContentHeight.topOffsetY) < abs(bottomY - estimatedContentHeight.bottomOffsetY) {
            estimatedContentHeight.topOffsetY
        } else {
            estimatedContentHeight.bottomOffsetY - bounds.height
        }
        setContentOffset(CGPointMake(contentOffset.x, offsetYToStopAt), animated: false)
    }

    func isVisible(_ view: UIView) -> Bool {
        if view.superview == nil {
             return false
        }
        return view.frame.intersects(CGRectMake(0, contentOffset.y, bounds.width, bounds.height))
    }
}

private func println(_ text: String) {
    print("\(Date.now.timeIntervalSince1970): \(text)")
}
