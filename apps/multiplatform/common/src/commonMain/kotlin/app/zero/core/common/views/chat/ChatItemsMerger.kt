package app.zero.core.common.views.chat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.*
import app.zero.core.common.model.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow

data class MergedItems (
  val items: List<MergedItem>,
  val splits: List<SplitRange>,
  val indexInParentItems: Map<Long, Int>,
) {
  companion object {
    fun create(items: List<ChatItem>, unreadCount: State<Int>, revealedItems: Set<Long>, chatState: ActiveChatState): MergedItems {
      if (items.isEmpty()) return MergedItems(emptyList(), emptyList(), emptyMap())

      val unreadAfterItemId = chatState.unreadAfterItemId
      val itemSplits = chatState.splits.value
      val mergedItems = ArrayList<MergedItem>()
      val splitRanges = ArrayList<SplitRange>()
      val indexInParentItems = mutableMapOf<Long, Int>()
      var index = 0
      var unclosedSplitIndex: Int? = null
      var unclosedSplitIndexInParent: Int? = null
      var visibleItemIndexInParent = -1
      var unreadBefore = unreadCount.value - chatState.unreadAfterNewestLoaded.value
      var lastRevealedIdsInMergedItems: MutableList<Long>? = null
      var lastRangeInReversedForMergedItems: MutableStateFlow<IntRange>? = null
      var recent: MergedItem? = null
      while (index < items.size) {
        val item = items[index]
        val prev = items.getOrNull(index - 1)
        val next = items.getOrNull(index + 1)
        val category = item.mergeCategory
        val itemIsSplit = itemSplits.contains(item.id)

        if (item.id == unreadAfterItemId.value) {
          unreadBefore = unreadCount.value - chatState.unreadAfter.value
        }
        if (item.isRcvNew) unreadBefore--

        val revealed = item.mergeCategory == null || revealedItems.contains(item.id)
        if (recent is MergedItem.Grouped && recent.mergeCategory == category && !revealedItems.contains(recent.items.first().item.id) && !itemIsSplit) {
          val listItem = ListItem(item, prev, next, unreadBefore)
          recent.items.add(listItem)

          if (item.isRcvNew) {
            recent.unreadIds.add(item.id)
          }
          if (lastRevealedIdsInMergedItems != null && lastRangeInReversedForMergedItems != null) {
            if (revealed) {
              lastRevealedIdsInMergedItems += item.id
            }
            lastRangeInReversedForMergedItems.value = lastRangeInReversedForMergedItems.value.first..index
          }
        } else {
          visibleItemIndexInParent++
          val listItem = ListItem(item, prev, next, unreadBefore)
          recent = if (item.mergeCategory != null) {
            if (item.mergeCategory != prev?.mergeCategory || lastRevealedIdsInMergedItems == null) {
              lastRevealedIdsInMergedItems = if (revealedItems.contains(item.id)) mutableListOf(item.id) else mutableListOf()
            } else if (revealed) {
              lastRevealedIdsInMergedItems += item.id
            }
            lastRangeInReversedForMergedItems = MutableStateFlow(index .. index)
            MergedItem.Grouped(
              items = arrayListOf(listItem),
              revealed = revealed,
              revealedIdsWithinGroup = lastRevealedIdsInMergedItems,
              rangeInReversed = lastRangeInReversedForMergedItems,
              mergeCategory = item.mergeCategory,
              startIndexInReversedItems = index,
              unreadIds = if (item.isRcvNew) mutableSetOf(item.id) else mutableSetOf()
            )
          } else {
            lastRangeInReversedForMergedItems = null
            MergedItem.Single(
              item = listItem,
              startIndexInReversedItems = index
            )
          }
          mergedItems.add(recent)
        }
        if (itemIsSplit) {
          if (unclosedSplitIndex != null && unclosedSplitIndexInParent != null) {
            splitRanges.add(SplitRange(unclosedSplitIndex until index, unclosedSplitIndexInParent until visibleItemIndexInParent))
          }
          unclosedSplitIndex = index
          unclosedSplitIndexInParent = visibleItemIndexInParent
        } else if (index + 1 == items.size && unclosedSplitIndex != null && unclosedSplitIndexInParent != null) {
          splitRanges.add(SplitRange(unclosedSplitIndex .. index, unclosedSplitIndexInParent .. visibleItemIndexInParent))
        }
        indexInParentItems[item.id] = visibleItemIndexInParent
        index++
      }
      return MergedItems(
        mergedItems,
        splitRanges,
        indexInParentItems
      )
    }
  }
}

sealed class MergedItem {
  abstract val startIndexInReversedItems: Int

  data class Single(
    val item: ListItem,
    override val startIndexInReversedItems: Int,
  ): MergedItem()

  @Stable
  data class Grouped (
    val items: ArrayList<ListItem>,
    val revealed: Boolean,

    val revealedIdsWithinGroup: MutableList<Long>,
    val rangeInReversed: MutableStateFlow<IntRange>,
    val mergeCategory: CIMergeCategory?,
    val unreadIds: MutableSet<Long>,
    override val startIndexInReversedItems: Int,
  ): MergedItem() {
    fun reveal(reveal: Boolean, revealedItems: MutableState<Set<Long>>) {
      val newRevealed = revealedItems.value.toMutableSet()
      var i = 0
      if (reveal) {
        while (i < items.size) {
          newRevealed.add(items[i].item.id)
          i++
        }
      } else {
        while (i < revealedIdsWithinGroup.size) {
          newRevealed.remove(revealedIdsWithinGroup[i])
          i++
        }
        revealedIdsWithinGroup.clear()
      }
      revealedItems.value = newRevealed
    }
  }

  fun hasUnread(): Boolean = when (this) {
    is Single -> item.item.isRcvNew
    is Grouped -> unreadIds.isNotEmpty()
  }

  fun newest(): ListItem = when (this) {
    is Single -> item
    is Grouped -> items.first()
  }

  fun oldest(): ListItem = when (this) {
    is Single -> item
    is Grouped -> items.last()
  }

  fun lastIndexInReversed(): Int = when (this) {
    is Single -> startIndexInReversedItems
    is Grouped -> startIndexInReversedItems + items.lastIndex
  }
}

data class SplitRange(

  val indexRangeInReversed: IntRange,

  val indexRangeInParentItems: IntRange
)

data class ListItem(
  val item: ChatItem,
  val prevItem: ChatItem?,
  val nextItem: ChatItem?,
  val unreadBefore: Int
)

data class ActiveChatState (
  val splits: MutableStateFlow<List<Long>> = MutableStateFlow(emptyList()),
  val unreadAfterItemId: MutableStateFlow<Long> = MutableStateFlow(-1L),
  val totalAfter: MutableStateFlow<Int> = MutableStateFlow(0),
  val unreadTotal: MutableStateFlow<Int> = MutableStateFlow(0),
  val unreadAfter: MutableStateFlow<Int> = MutableStateFlow(0),
  val unreadAfterNewestLoaded: MutableStateFlow<Int> = MutableStateFlow(0),
  @Volatile var selectionActive: Boolean = false
) {
  fun moveUnreadAfterItem(toItemId: Long?, nonReversedItems: List<ChatItem>) {
    toItemId ?: return
    val currentIndex = nonReversedItems.indexOfFirst { it.id == unreadAfterItemId.value }
    val newIndex = nonReversedItems.indexOfFirst { it.id == toItemId }
    if (currentIndex == -1 || newIndex == -1) return
    unreadAfterItemId.value = toItemId
    val unreadDiff = if (newIndex > currentIndex) {
      -nonReversedItems.subList(currentIndex + 1, newIndex + 1).count { it.isRcvNew }
    } else {
      nonReversedItems.subList(newIndex + 1, currentIndex + 1).count { it.isRcvNew }
    }
    unreadAfter.value += unreadDiff
  }

  fun moveUnreadAfterItem(fromIndex: Int, toIndex: Int, nonReversedItems: List<ChatItem>) {
    if (fromIndex == -1 || toIndex == -1) return
    unreadAfterItemId.value = nonReversedItems[toIndex].id
    val unreadDiff = if (toIndex > fromIndex) {
      -nonReversedItems.subList(fromIndex + 1, toIndex + 1).count { it.isRcvNew }
    } else {
      nonReversedItems.subList(toIndex + 1, fromIndex + 1).count { it.isRcvNew }
    }
    unreadAfter.value += unreadDiff
  }

  fun clear() {
    splits.value = emptyList()
    unreadAfterItemId.value = -1L
    totalAfter.value = 0
    unreadTotal.value = 0
    unreadAfter.value = 0
    unreadAfterNewestLoaded.value = 0
  }

  fun itemsRead(itemIds: Set<Long>?, newItems: List<ChatItem>) {
    if (itemIds == null) {
      unreadTotal.value = 0
      unreadAfter.value = 0
      return
    }
    var unreadAfterItemIndex: Int = -1
    var i = newItems.lastIndex
    val ids = itemIds.toMutableSet()
    var newUnreadTotal = unreadTotal.value
    var newUnreadAfter = unreadAfter.value
    while (i >= 0) {
      val item = newItems[i]
      if (item.id == unreadAfterItemId.value) {
        unreadAfterItemIndex = i
      }
      if (ids.contains(item.id)) {
        if (unreadAfterItemIndex == -1) {
          newUnreadAfter--
        }
        newUnreadTotal--
        ids.remove(item.id)
        if (ids.isEmpty()) break
      }
      i--
    }
    unreadTotal.value = newUnreadTotal
    unreadAfter.value = newUnreadAfter
  }

  fun itemAdded(item: Pair<Long, Boolean>) {
    if (item.second) {
      unreadAfter.value++
      unreadTotal.value++
    }
  }

  fun itemsRemoved(itemIds: List<Triple<Long, Int, Boolean>>, newItems: List<ChatItem>) {
    val newSplits = ArrayList<Long>()
    for (split in splits.value) {
      val index = itemIds.indexOfFirst { it.first == split }
      if (index != -1) {
        val newSplit = newItems.getOrNull(itemIds[index].second - itemIds.count { it.second <= index })?.id
        if (newSplit != null && !newSplits.contains(newSplit)) {
          newSplits.add(newSplit)
        }
      } else {
        newSplits.add(split)
      }
    }
    splits.value = newSplits

    val index = itemIds.indexOfFirst { it.first == unreadAfterItemId.value }
    if (index != -1) {
      var newUnreadAfterItemId = newItems.getOrNull(itemIds[index].second - itemIds.count { it.second <= index })?.id
      val newUnreadAfterItemWasNull = newUnreadAfterItemId == null
      if (newUnreadAfterItemId == null) {
        newUnreadAfterItemId = newItems.firstOrNull()?.id
      }
      if (newUnreadAfterItemId != null) {
        unreadAfterItemId.value = newUnreadAfterItemId
        totalAfter.value -= itemIds.count { it.second > index }
        unreadTotal.value -= itemIds.count { it.second <= index && it.third }
        unreadAfter.value -= itemIds.count { it.second > index && it.third }
        if (newUnreadAfterItemWasNull) {
          if (newItems.firstOrNull()?.isRcvNew == true) {
            unreadTotal.value++
            unreadAfter.value--
          }
        }
      } else {
        unreadAfterItemId.value = -1L
        totalAfter.value = 0
        unreadTotal.value = 0
        unreadAfter.value = 0
      }
    } else {
      totalAfter.value -= itemIds.size
    }
  }
}

fun visibleItemIndexesNonReversed(mergedItems: State<MergedItems>, reversedItemsSize: Int, listState: LazyListState): IntRange {
  val zero = 0 .. 0
  if (listState.layoutInfo.totalItemsCount == 0) return zero
  val newest = mergedItems.value.items.getOrNull(listState.firstVisibleItemIndex)?.startIndexInReversedItems
  val oldest = mergedItems.value.items.getOrNull(listState.layoutInfo.visibleItemsInfo.last().index)?.lastIndexInReversed()
  if (newest == null || oldest == null) return zero
  val range = reversedItemsSize - oldest .. reversedItemsSize - newest
  if (range.first < 0 || range.last < 0) return zero

  return range
}

