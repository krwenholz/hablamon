/// Levenshtein distance between two strings, counted in Characters.
func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a)
    let b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        current[0] = i
        for j in 1...b.count {
            let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
            current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
        }
        swap(&previous, &current)
    }
    return previous[b.count]
}

/// Similarity in 0–1, where 1 means identical.
func similarity(_ a: String, _ b: String) -> Double {
    let longest = max(a.count, b.count)
    guard longest > 0 else { return 1 }
    return 1 - Double(editDistance(a, b)) / Double(longest)
}
