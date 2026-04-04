import SwiftUI
import Zero

struct MergedItems: Hashable, Equatable {
    let im: ItemsModel
    let items: [MergedItem]
    let splits: [SplitRange]
    let indexInParentItems: Dictionary<Int64, Int>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine("\(items.hashValue)")
    }

    static func create(_ im: ItemsModel, _ revealedItems: Set<Int64>) -> MergedItems {
        if im.reversedChatItems.isEmpty {
            return MergedItems(im: im, items: [], splits: [], indexInParentItems: [:])
        }

        let unreadCount = im.chatState.unreadTotal

        let unreadAfterItemId = im.chatState.unreadAfterItemId
        let itemSplits = im.chatState.splits
        var mergedItems: [MergedItem] = []
        var splitRanges: [SplitRange] = []
        var indexInParentItems = Dictionary<Int64, Int>()
        var index = 0
        var unclosedSplitIndex: Int? = nil
        var unclosedSplitIndexInParent: Int? = nil
        var visibleItemIndexInParent = -1
        var unreadBefore = unreadCount - im.chatState.unreadAfterNewestLoaded
        var lastRevealedIdsInMergedItems: BoxedValue<[Int64]>? = nil
        var lastRangeInReversedForMergedItems: BoxedValue<ClosedRange<Int>>? = nil
        var recent: MergedItem? = nil
        while index < im.reversedChatItems.count {
            let item = im.reversedChatItems[index]
            let prev = index >= 1 ? im.reversedChatItems[index - 1] : nil
            let next = index + 1 < im.reversedChatItems.count ? im.reversedChatItems[index + 1] : nil
            let category = item.mergeCategory
            let itemIsSplit = itemSplits.contains(item.id)

            if item.id == unreadAfterItemId {
                unreadBefore = unreadCount - im.chatState.unreadAfter
            }
            if item.isRcvNew {
                unreadBefore -= 1
            }

            let revealed = item.mergeCategory == nil || revealedItems.contains(item.id)
            if recent != nil, case let .grouped(items, _, _, _, mergeCategory, unreadIds, _, _) = recent, mergeCategory == category, let first = items.boxedValue.first, !revealedItems.contains(first.item.id) && !itemIsSplit {
                let listItem = ListItem(item: item, prevItem: prev, nextItem: next, unreadBefore: unreadBefore)
                items.boxedValue.append(listItem)

                if item.isRcvNew {
                    unreadIds.boxedValue.insert(item.id)
                }
                if let lastRevealedIdsInMergedItems, let lastRangeInReversedForMergedItems {
                    if revealed {
                        lastRevealedIdsInMergedItems.boxedValue.append(item.id)
                    }
                    lastRangeInReversedForMergedItems.boxedValue = lastRangeInReversedForMergedItems.boxedValue.lowerBound ... index
                }
            } else {
                visibleItemIndexInParent += 1
                let listItem = ListItem(item: item, prevItem: prev, nextItem: next, unreadBefore: unreadBefore)
                if item.mergeCategory != nil {
                    if item.mergeCategory != prev?.mergeCategory || lastRevealedIdsInMergedItems == nil {
                        lastRevealedIdsInMergedItems = BoxedValue(revealedItems.contains(item.id) ? [item.id] : [])
                    } else if revealed, let lastRevealedIdsInMergedItems {
                        lastRevealedIdsInMergedItems.boxedValue.append(item.id)
                    }
                    lastRangeInReversedForMergedItems = BoxedValue(index ... index)
                    recent = MergedItem.grouped(
                        items: BoxedValue([listItem]),
                        revealed: revealed,
                        revealedIdsWithinGroup: lastRevealedIdsInMergedItems!,
                        rangeInReversed: lastRangeInReversedForMergedItems!,
                        mergeCategory: item.mergeCategory,
                        unreadIds: BoxedValue(item.isRcvNew ? Set(arrayLiteral: item.id) : Set()),
                        startIndexInReversedItems: index,
                        hash: listItem.genHash(revealedItems.contains(prev?.id ?? -1), revealedItems.contains(next?.id ?? -1))
                    )
                } else {
                    lastRangeInReversedForMergedItems = nil
                    recent = MergedItem.single(
                        item: listItem,
                        startIndexInReversedItems: index,
                        hash: listItem.genHash(revealedItems.contains(prev?.id ?? -1), revealedItems.contains(next?.id ?? -1))
                    )
                }
                mergedItems.append(recent!)
            }
            if itemIsSplit {
                if let unclosedSplitIndex, let unclosedSplitIndexInParent {
                    splitRanges.append(SplitRange(itemId: im.reversedChatItems[unclosedSplitIndex].id, indexRangeInReversed: unclosedSplitIndex ... index - 1, indexRangeInParentItems: unclosedSplitIndexInParent ... visibleItemIndexInParent - 1))
                }
                unclosedSplitIndex = index
                unclosedSplitIndexInParent = visibleItemIndexInParent
            } else if index + 1 == im.reversedChatItems.count, let unclosedSplitIndex, let unclosedSplitIndexInParent {
                splitRanges.append(SplitRange(itemId: im.reversedChatItems[unclosedSplitIndex].id, indexRangeInReversed: unclosedSplitIndex ... index, indexRangeInParentItems: unclosedSplitIndexInParent ... visibleItemIndexInParent))
            }
            indexInParentItems[item.id] = visibleItemIndexInParent
            index += 1
        }
        return MergedItems(
            im: im,
            items: mergedItems,
            splits: splitRanges,
            indexInParentItems: indexInParentItems
        )
    }

    func isActualState() -> Bool {
        return indexInParentItems.count == im.reversedChatItems.count &&
        splits.count == im.chatState.splits.count &&
        ((splits.count == 1 && splits[0].itemId == im.chatState.splits[0]) || splits.map({ split in split.itemId }).sorted() == im.chatState.splits.sorted())
    }
}

enum MergedItem: Identifiable, Hashable, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hash == rhs.hash
    }

    var id: Int64 { newest().item.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hash)
    }

    var hash: String {
        switch self {
        case .single(_, _, let hash): hash + " 1"
        case .grouped(let items, _, _, _, _, _, _, let hash): hash + " \(items.boxedValue.count)"
        }
    }

    case single(
        item: ListItem,
        startIndexInReversedItems: Int,
        hash: String
    )

    case grouped (
        items: BoxedValue<[ListItem]>,
        revealed: Bool,

        revealedIdsWithinGroup: BoxedValue<[Int64]>,
        rangeInReversed: BoxedValue<ClosedRange<Int>>,
        mergeCategory: CIMergeCategory?,
        unreadIds: BoxedValue<Set<Int64>>,
        startIndexInReversedItems: Int,
        hash: String
    )

    func revealItems(_ reveal: Bool, _ revealedItems: Binding<Set<Int64>>) {
        if case .grouped(let items, _, let revealedIdsWithinGroup, _, _, _, _, _) = self {
            var newRevealed = revealedItems.wrappedValue
            var i = 0
            if reveal {
                while i < items.boxedValue.count {
                    newRevealed.insert(items.boxedValue[i].item.id)
                    i += 1
                }
            } else {
                while i < revealedIdsWithinGroup.boxedValue.count {
                    newRevealed.remove(revealedIdsWithinGroup.boxedValue[i])
                    i += 1
                }
                revealedIdsWithinGroup.boxedValue.removeAll()
            }
            revealedItems.wrappedValue = newRevealed
        }
    }

    var startIndexInReversedItems: Int {
        get {
            switch self {
            case let .single(_, startIndexInReversedItems, _): startIndexInReversedItems
            case let .grouped(_, _, _, _, _, _, startIndexInReversedItems, _): startIndexInReversedItems
            }
        }
    }

    func hasUnread() -> Bool {
        switch self {
        case let .single(item, _, _): item.item.isRcvNew
        case let .grouped(_, _, _, _, _, unreadIds, _, _): !unreadIds.boxedValue.isEmpty
        }
    }

    func newest() -> ListItem {
        switch self {
        case let .single(item, _, _): item
        case let .grouped(items, _, _, _, _, _, _, _): items.boxedValue[0]
        }
    }

    func oldest() -> ListItem {
        switch self {
        case let .single(item, _, _): item
        case let .grouped(items, _, _, _, _, _, _, _): items.boxedValue[items.boxedValue.count - 1]
        }
    }

    func lastIndexInReversed() -> Int {
        switch self {
        case .single: startIndexInReversedItems
        case let .grouped(items, _, _, _, _, _, _, _): startIndexInReversedItems + items.boxedValue.count - 1
        }
    }
}

struct SplitRange {
    let itemId: Int64

    let indexRangeInReversed: ClosedRange<Int>

    let indexRangeInParentItems: ClosedRange<Int>
}

struct ListItem: Hashable {
    let item: ChatItem
    let prevItem: ChatItem?
    let nextItem: ChatItem?
    let unreadBefore: Int

    private func chatDirHash(_ chatDir: CIDirection?) -> Int {
        guard let chatDir else { return 0 }
        return switch chatDir {
        case .directSnd: 0
        case .directRcv: 1
        case .groupSnd: 2
        case let .groupRcv(mem): "\(mem.groupMemberId) \(mem.displayName) \(mem.memberStatus.rawValue) \(mem.memberRole.rawValue) \(mem.image?.hash ?? 0)".hash
        case .channelRcv: 3
        case .localSnd: 4
        case .localRcv: 5
        }
    }

    func genHash(_ prevRevealed: Bool, _ nextRevealed: Bool) -> String {
        "\(item.meta.itemId) \(item.meta.updatedAt.hashValue) \(item.meta.itemEdited) \(item.meta.itemDeleted?.hashValue ?? 0) \(item.meta.itemTimed?.hashValue ?? 0) \(item.meta.itemStatus.hashValue) \(item.meta.sentViaProxy ?? false) \(item.mergeCategory?.hashValue ?? 0) \(chatDirHash(item.chatDir)) \(item.reactions.hashValue) \(item.meta.isRcvNew) \(item.text.hash) \(item.file?.hashValue ?? 0) \(item.quotedItem?.itemId ?? 0) \(unreadBefore) \(prevItem?.id ?? 0) \(chatDirHash(prevItem?.chatDir)) \(prevItem?.mergeCategory?.hashValue ?? 0) \(prevRevealed) \(nextItem?.id ?? 0) \(chatDirHash(nextItem?.chatDir)) \(nextItem?.mergeCategory?.hashValue ?? 0) \(nextRevealed)"
    }
}

class ActiveChatState {
    var splits: [Int64] = []
    var unreadAfterItemId: Int64 = -1
    var totalAfter: Int = 0
    var unreadTotal: Int = 0
    var unreadAfter: Int = 0
    var unreadAfterNewestLoaded: Int = 0

    func moveUnreadAfterItem(_ toItemId: Int64?, _ nonReversedItems: [ChatItem]) {
        guard let toItemId else { return }
        let currentIndex = nonReversedItems.firstIndex(where: { $0.id == unreadAfterItemId })
        let newIndex = nonReversedItems.firstIndex(where: { $0.id == toItemId })
        guard let currentIndex, let newIndex else {
            return
        }
        unreadAfterItemId = toItemId
        let unreadDiff = newIndex > currentIndex
        ? -nonReversedItems[currentIndex + 1..<newIndex + 1].filter { $0.isRcvNew }.count
        : nonReversedItems[newIndex + 1..<currentIndex + 1].filter { $0.isRcvNew }.count
        unreadAfter += unreadDiff
    }

    func moveUnreadAfterItem(_ fromIndex: Int, _ toIndex: Int, _ nonReversedItems: [ChatItem]) {
        if fromIndex == -1 || toIndex == -1 {
            return
        }
        unreadAfterItemId = nonReversedItems[toIndex].id
        let unreadDiff = toIndex > fromIndex
        ? -nonReversedItems[fromIndex + 1..<toIndex + 1].filter { $0.isRcvNew }.count
        : nonReversedItems[toIndex + 1..<fromIndex + 1].filter { $0.isRcvNew }.count
        unreadAfter += unreadDiff
    }

    func clear() {
        splits = []
        unreadAfterItemId = -1
        totalAfter = 0
        unreadTotal = 0
        unreadAfter = 0
        unreadAfterNewestLoaded = 0
    }

    func itemsRead(_ itemIds: Set<Int64>?, _ newItems: [ChatItem]) {
        guard let itemIds else {
            unreadTotal = 0
            unreadAfter = 0
            return
        }
        var unreadAfterItemIndex: Int = -1
        var i = newItems.count - 1
        var ids = itemIds
        var newUnreadTotal = unreadTotal
        var newUnreadAfter = unreadAfter
        while i >= 0 {
            let item = newItems[i]
            if item.id == unreadAfterItemId {
                unreadAfterItemIndex = i
            }
            if ids.contains(item.id) {
                if (unreadAfterItemIndex == -1) {
                    newUnreadAfter -= 1
                }
                newUnreadTotal -= 1
                ids.remove(item.id)
                if ids.isEmpty {
                    break
                }
            }
            i -= 1
        }
        unreadTotal = newUnreadTotal
        unreadAfter = newUnreadAfter
    }

    func itemAdded(_ item: (Int64, Bool), _ index: Int) {
        if item.1 {
            unreadAfter += 1
            unreadTotal += 1
        }
    }

    func itemsRemoved(_ itemIds: [(Int64, Int, Bool)], _ newItems: [ChatItem]) {
        var newSplits: [Int64] = []
        for split in splits {
            let index = itemIds.firstIndex(where: { (delId, _, _) in delId == split })
            if let index {
                let idx = itemIds[index].1 - itemIds.filter { (_, delIndex, _) in delIndex <= index }.count
                let newSplit = newItems.count > idx && idx >= 0 ? newItems[idx].id : nil
                if let newSplit, !newSplits.contains(newSplit) {
                    newSplits.append(newSplit)
                }
            } else {
                newSplits.append(split)
            }
        }
        splits = newSplits

        let index = itemIds.firstIndex(where: { (delId, _, _) in delId == unreadAfterItemId })
        if let index {
            let idx = itemIds[index].1 - itemIds.filter { (_, delIndex, _) in delIndex <= index }.count
            var newUnreadAfterItemId = newItems.count > idx && idx >= 0 ? newItems[idx].id : nil
            let newUnreadAfterItemWasNull = newUnreadAfterItemId == nil
            if newUnreadAfterItemId == nil {
                newUnreadAfterItemId = newItems.first?.id
            }
            if let newUnreadAfterItemId {
                unreadAfterItemId = newUnreadAfterItemId
                totalAfter -= itemIds.filter { (_, delIndex, _) in delIndex > index }.count
                unreadTotal -= itemIds.filter { (_, delIndex, isRcvNew) in delIndex <= index && isRcvNew }.count
                unreadAfter -= itemIds.filter { (_, delIndex, isRcvNew) in delIndex > index && isRcvNew }.count
                if newUnreadAfterItemWasNull {
                    if newItems.first?.isRcvNew == true {
                        unreadTotal += 1
                        unreadAfter -= 1
                    }
                }
            } else {
                unreadAfterItemId = -1
                totalAfter = 0
                unreadTotal = 0
                unreadAfter = 0
            }
        } else {
            totalAfter -= itemIds.count
        }
    }
}

class BoxedValue<T: Hashable>: Equatable, Hashable {
    static func == (lhs: BoxedValue<T>, rhs: BoxedValue<T>) -> Bool {
        lhs.boxedValue == rhs.boxedValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine("\(self)")
    }

    var boxedValue : T
    init(_ value: T) {
        self.boxedValue = value
    }
}

@MainActor
func visibleItemIndexesNonReversed(_ im: ItemsModel, _ listState: EndlessScrollView<MergedItem>.ListState, _ mergedItems: MergedItems) -> ClosedRange<Int> {
    let zero = 0 ... 0
    let items = mergedItems.items
    if items.isEmpty {
        return zero
    }
    let newest = items.count > listState.firstVisibleItemIndex ? items[listState.firstVisibleItemIndex].startIndexInReversedItems : nil
    let oldest = items.count > listState.lastVisibleItemIndex ? items[listState.lastVisibleItemIndex].lastIndexInReversed() : nil
    guard let newest, let oldest else {
        return zero
    }
    let size = im.reversedChatItems.count
    let range = size - oldest ... size - newest
    if range.lowerBound < 0 || range.upperBound < 0 {
        return zero
    }

    return range
}
