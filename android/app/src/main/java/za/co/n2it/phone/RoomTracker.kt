package za.co.n2it.phone

/**
 * Conference cards: works out who has left a room from the PBX's member list (`/app/n2it/room.php`, 2026-11-06).
 * Cautious on purpose, because a card must never go while the person can still hear the call:
 *  - a card is only tied to a member once its number has been seen in the room, so someone still being moved in stays;
 *  - a card only goes after its member has been missing from two lists in a row.
 * Plain Kotlin with no Android calls.
 */
internal class RoomTracker {
    data class Member(val id: Int, val match: String, val self: Boolean, val number: String = "", val name: String = "")

    private val learned = HashMap<String, Int>()   // card id -> room member id
    private val missing = HashMap<String, Int>()   // card id -> lists in a row without them
    private val waiting = HashMap<String, Int>()   // card id -> lists without ever finding their person

    fun reset() { learned.clear(); missing.clear(); waiting.clear() }

    /** [cards] = card id to number. Returns the ids of the cards whose person has left. */
    fun update(members: List<Member>, cards: List<Pair<String, String>>): List<String> {
        val others = members.filter { !it.self }
        val ids = others.map { it.id }.toSet()
        learned.keys.retainAll(cards.map { it.first }.toSet())
        missing.keys.retainAll(learned.keys)
        val taken = learned.values.toMutableSet()
        for ((card, number) in cards) {
            if (card in learned) continue
            val key = matchKey(number)
            val m = others.firstOrNull { it.id !in taken && it.match == key } ?: continue
            learned[card] = m.id
            taken += m.id
        }
        val gone = mutableListOf<String>()
        for ((card, id) in learned) {
            if (id in ids) { missing.remove(card); continue }
            val n = (missing[card] ?: 0) + 1
            missing[card] = n
            if (n >= 2) gone += card
        }
        gone.forEach { learned.remove(it); missing.remove(it) }
        return gone
    }

    /** The room member behind a card, for removing them. */
    fun memberOf(card: String) = learned[card]

    /** Cards never matched after 5 lists (15 s): someone else answered that call, or it never joined. They go quietly. */
    fun stale(cards: List<String>): List<String> {
        waiting.keys.retainAll(cards.toSet())
        val old = cards.filter { it !in learned }.filter { c -> (waiting.merge(c, 1, Int::plus) ?: 0) >= 5 }
        old.forEach { waiting.remove(it) }
        return old
    }

    /** Members in the room with no card yet: someone the host of the room added, or everyone on a phone that was moved in. */
    fun untied(members: List<Member>) = members.filter { !it.self && it.id !in learned.values }

    companion object {
        /** Same rule as the PBX's "match": digits only, the last 9 when there are 9 or more, so 082…, 2782… and +2782… agree. */
        fun matchKey(number: String): String {
            val digits = number.substringBefore('@').filter { it.isDigit() }
            return if (digits.length >= 9) digits.takeLast(9) else digits
        }
    }
}
