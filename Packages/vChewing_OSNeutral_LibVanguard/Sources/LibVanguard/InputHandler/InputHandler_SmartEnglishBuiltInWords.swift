// (c) 2022 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

// MARK: - 智慧中英輸入自動切換：內建英文單字清單

/// 智慧中英自動切換的內建英文單字清單：輸入鍵序列（整段）恰好拼成其中之一時立即轉英。
///
/// 收錄原則（以大千排列逐字模擬輸入、以 `SmartEnglishTrailAnalyzer` 判定）：
/// - 主體：英文詞頻前 1000 名（google-10000-english，USA、不含粗話）中長度 ≥ 3、
///   違規 ≥ 2 次（與注音輸入順序完全不相干）、且預設門檻 5 之下打完整字都不會因連續誤鍵自動轉英者。
///   違規 0–1 次者（按鍵順序即為或近似合理注音，例如 `top` ＝ ㄔㄟ→ㄣ）一律不收，以免攔截正常中文；
///   打字途中即會因連續誤鍵自動轉英者亦不收（收了也輪不到觸發）。
/// - 另收少數詞頻較低、但經使用者指定的字（`vpn`、`zoo`、`cal`、`tea`）。
///
/// 只收小寫：Shift+字母會以 `_letter_X` 併入組字區並自序列移除，大寫鍵本就不會留在序列中。
/// 判定於每一鍵之後進行，故互為前綴的單字（例如 `new` 與 `news`）由較短者先觸發；
/// 其後的按鍵在英數暫存模式中照常輸出，客體收到的內容不變。
enum SmartEnglishBuiltInWords {
  static let all: Set<String> = [
    // 英文詞頻前 1000 名之中、與注音輸入順序完全不相干者（依詞頻排序）。
    "the", "and", "for", "that", "this", "with", "you", "not", "are", "from", "your", "have", "new", "more", "was",
    "home", "can", "about", "page", "has", "free", "but", "our", "one", "time", "they", "site", "may", "what",
    "which", "their", "news", "out", "use", "any", "there", "see", "only", "his", "when", "here", "web", "now",
    "get", "view", "online", "first", "been", "would", "how", "were", "some", "these", "its", "than", "find",
    "price", "date", "back", "people", "had", "list", "name", "just", "over", "state", "year", "day", "into",
    "email", "two", "health", "world", "next", "used", "work", "last", "most", "music", "buy", "data", "make",
    "them", "should", "post", "her", "city", "add", "policy", "number", "such", "please", "support", "after", "best",
    "then", "jan", "good", "video", "well", "where", "info", "public", "books", "high", "school", "each", "links",
    "she", "years", "very", "read", "group", "need", "many", "user", "said", "does", "set", "under", "mail", "map",
    "life", "know", "games", "way", "days", "part", "could", "great", "hotel", "real", "item", "ebay", "must",
    "store", "travel", "made", "report", "off", "details", "line", "terms", "before", "hotels", "did", "send",
    "right", "type", "local", "those", "using", "results", "national", "car", "take", "area", "want", "phone", "dvd",
    "forum", "family", "long", "based", "code", "show", "even", "black", "check", "special", "index", "being",
    "women", "much", "sign", "open", "today", "south", "case", "same", "pages", "section", "own", "found", "sports",
    "house", "both", "photo", "game", "power", "while", "care", "down", "three", "total", "place", "end", "him",
    "per", "think", "north", "posts", "big", "media", "law", "water", "history", "size", "art", "since", "guide",
    "board", "location", "white", "text", "small", "rate", "during", "usa", "times", "sites", "level", "digital",
    "profile", "form", "love", "john", "main", "call", "hours", "title", "why", "shall", "class", "still", "money",
    "quality", "every", "little", "visit", "save", "tools", "low", "reply", "movies", "college", "value", "york",
    "man", "card", "jobs", "food", "author", "press", "learn", "sale", "print", "teen", "room", "stock", "too",
    "point", "men", "west", "sales", "left", "team", "select", "windows", "photos", "gay", "week", "note", "live",
    "large", "table", "june", "really", "action", "start", "model", "air", "plan", "human", "yes", "hot", "cost",
    "movie", "say", "july", "yahoo", "going", "test", "come", "dec", "study", "cart", "staff", "san", "again",
    "play", "looking", "april", "never", "users", "topic", "working", "tax", "person", "below", "mobile", "less",
    "got", "party", "login", "let", "legal", "above", "park", "stores", "side", "act", "red", "give", "social",
    "quote", "story", "sell", "options", "rates", "key", "body", "young", "field", "few", "east", "single", "age",
    "club", "example", "girls", "road", "gift", "night", "hard", "texas", "oct", "pay", "four", "poker", "status",
    "browse", "range", "building", "court", "always", "result", "audio", "light", "write", "war", "nov", "blue",
    "groups", "easy", "given", "files", "event", "fax", "china", "making", "needs", "might", "yet", "month", "major",
    "star", "areas", "future", "space", "hand", "sun", "cards", "london", "rss", "child", "keep", "enter", "share",
    "schools", "million", "added", "baby", "run", "net", "popular", "term", "film", "put", "reports", "try",
    "notice", "head", "radio", "until", "cell", "color", "self", "council", "away", "track", "once", "least", "sure",
    "faq", "trade", "edition", "cars", "tell", "able", "david", "fun", "green", "close", "drive", "feb", "called",
    "short", "arts", "lot", "display", "means", "daily", "beach", "past", "natural", "five", "upon", "period",
    "says", "mar", "land", "done", "window", "pro", "region", "costs", "style", "front", "update", "parts", "aug",
    "ever", "early", "miles", "sound", "word", "works", "apr", "rules", "final", "adult", "thing", "cheap", "kids",
    "true", "else", "mark", "third", "gifts", "europe", "topics", "bad", "plus", "auto", "cover", "edit", "videos",
    "fast", "fact", "unit", "global", "tech", "meet", "far", "often", "submit", "amount", "watch", "feel", "bank",
    "thanks", "deals", "words", "linux", "james", "town", "heart", "choose", "points", "error", "jun", "girl",
    "toys", "clear", "golf", "domain", "makes", "loan", "wide", "india", "position", "taken", "sort", "models",
    "known", "half", "cases", "step", "florida", "simple", "quick", "none", "paul", "lake", "whole", "annual",
    "basic", "sony", "shows", "google", "fire", "holiday", "chat", "along", "among", "death", "speed", "html",
    "loss", "face", "brand", "bit", "yellow", "political", "base", "near", "stuff", "japan", "doing", "loans",
    "shoes", "entry", "stay", "nature",
    // 使用者指定。
    "vpn", "zoo", "cal", "tea",
  ]
}
