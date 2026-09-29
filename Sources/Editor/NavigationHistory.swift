import Foundation

final class NavigationHistory {
    private var positions: [Int] = []
    private var cursor = -1
    func record(from: Int, to: Int) {
        guard from != to else { return }
        if cursor + 1 < positions.count { positions.removeSubrange((cursor + 1)..<positions.count) }
        if positions.last != from { positions.append(from) }
        if positions.last != to { positions.append(to) }
        if positions.count > 200 { positions.removeFirst(positions.count - 200) }
        cursor = positions.count - 1
    }
    func move(backwards: Bool) -> Int? {
        let next = cursor + (backwards ? -1 : 1)
        guard positions.indices.contains(next) else { return nil }
        cursor = next; return positions[next]
    }
    func apply(_ edits: [TextEdit]) {
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) { positions = positions.map { EditTransaction.transformed($0, by: edit) } }
    }
}
