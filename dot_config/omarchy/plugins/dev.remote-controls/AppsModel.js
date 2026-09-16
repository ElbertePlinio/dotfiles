function matchingEntries(entries, query) {
    var needle = String(query || "").trim().toLowerCase();
    return entries.filter(function(entry) {
        if (!entry || !entry.id || entry.noDisplay || entry.hidden) return false;
        var text = [entry.name || entry.id, entry.genericName || "", entry.comment || ""].join(" ").toLowerCase();
        return text.indexOf(needle) !== -1;
    }).slice().sort(function(a, b) {
        return String(a.name || a.id).localeCompare(String(b.name || b.id));
    });
}
