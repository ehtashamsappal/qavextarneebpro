/// Pure-Dart trick-taking / capture / sevens engine (QAVEX card track).
/// No Flutter imports: runs headless under `flutter test`.
///
/// Covers: bid-trick games (callbreak, spades, tarneeb, contract whist),
/// avoid-points (hearts), point-tricks (twenty-nine, skat, pinochle,
/// briscola), take-it trump (euchre), court-piece team play, capture games
/// (scopa, pishti) and sevens. Deep rules are simplified for mobile where
/// noted in each game's howto; the simplifications are documented, never
/// placeholders.

// ============================== cards ==============================

class TCard {
  final int suit; // 0=S 1=H 2=D 3=C
  final int rank; // std52: 1..13 (1=A); skat32: 7..14; euchre24/pinochle: 9..14 (14=A); briscola40: 1..7,11,12,13
  const TCard(this.suit, this.rank);
  String get suitChar => const ['S', 'H', 'D', 'C'][suit];
  String get rankLabel {
    if (rank == 14 || rank == 1) return 'A';
    if (rank == 13) return 'K';
    if (rank == 12) return 'Q';
    if (rank == 11) return 'J';
    return '$rank';
  }
  String get suitGlyph {
    switch (suit) {
      case 0:
        return '\u2660';
      case 1:
        return '\u2665';
      case 2:
        return '\u2666';
      default:
        return '\u2663';
    }
  }
  bool get isRed => suit == 1 || suit == 2;
  @override
  String toString() => '$rankLabel$suitChar';
  @override
  bool operator ==(Object other) =>
      other is TCard && other.suit == suit && other.rank == rank;
  @override
  int get hashCode => suit * 32 + rank;
}

class TrickPlay {
  final int seat;
  final TCard card;
  const TrickPlay(this.seat, this.card);
}

List<TCard> buildDeck(String deck) {
  final out = <TCard>[];
  if (deck == 'pinochle48') {
    for (int copy = 0; copy < 2; copy++) {
      for (int s = 0; s < 4; s++) {
        for (int r = 9; r <= 14; r++) {
          out.add(TCard(s, r));
        }
      }
    }
    return out;
  }
  List<int> ranks;
  switch (deck) {
    case 'skat32':
      ranks = const [7, 8, 9, 10, 11, 12, 13, 14];
      break;
    case 'briscola40':
      ranks = const [1, 2, 3, 4, 5, 6, 7, 11, 12, 13];
      break;
    case 'euchre24':
      ranks = const [9, 10, 11, 12, 13, 14];
      break;
    default:
      ranks = const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
  }
  for (int s = 0; s < 4; s++) {
    for (final r in ranks) {
      out.add(TCard(s, r));
    }
  }
  return out;
}

/// Card point value for point-trick games.
int cardPoints(TCard c, String table) {
  final r = c.rank;
  switch (table) {
    case 'twentynine':
      if (r == 11) return 3;
      if (r == 9) return 2;
      if (r == 14 || r == 10) return 1;
      return 0;
    case 'skat':
      if (r == 14) return 11;
      if (r == 10) return 10;
      if (r == 13) return 4;
      if (r == 12) return 3;
      if (r == 11) return 2;
      return 0;
    case 'pinochle':
      if (r == 14 || r == 10) return 10;
      if (r == 13 || r == 12) return 5;
      if (r == 11) return 2;
      return 0;
    case 'briscola':
      if (r == 1) return 11;
      if (r == 3) return 10;
      if (r == 13) return 4;
      if (r == 12) return 3;
      if (r == 11) return 2;
      return 0;
  }
  return 0;
}

class _SeededRandom {
  int _s;
  _SeededRandom(this._s);
  int nextInt(int max) {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s % max;
  }
  bool nextBool() => nextInt(2) == 1;
  void shuffle(List list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }
}

// ============================== config ==============================

class TrickConfig {
  final String gameId;
  final int players;
  final String deck; // std52|skat32|briscola40|euchre24|pinochle48
  final int handSize;
  final int tableCards; // capture games: cards dealt to the table
  final bool bidding; // a bidding phase happens before play
  final String trumpMode; // fixed|bid|none|random
  final int fixedTrump; // 0..3 when trumpMode == fixed
  final bool teamPlay; // 4-player partners (seat 0+2 vs 1+3)
  final String scoreMode; // bid|courtpiece|avoid|contract|spades|euchre|bridge|tarneeb|tricks|points|capture|sevens
  final String pointsRule; // twentynine|skat|pinochle|briscola (with scoreMode points)
  final String captureRule; // scopa|pishti (with scoreMode capture)
  final String uiMode; // trick|capture|sevens
  final int targetScore; // match ends when reached (meaning per scoreMode)
  final int rounds; // >0: fixed rounds, highest score wins
  final int roundWinsTarget; // >0: first to this many round wins (court piece)
  final int bidMin;
  final int bidMax;
  final String bidUnit; // tricks|points
  final String bidStyle; // number|takeIt
  final bool bowers; // euchre bowers
  final int heartsPts;
  final int queenSpadesPts;
  final int tricksToWin; // court piece: tricks for the calling team to win the round
  final String aiFlavor;
  const TrickConfig({
    required this.gameId,
    required this.players,
    required this.deck,
    required this.handSize,
    this.tableCards = 0,
    required this.bidding,
    required this.trumpMode,
    this.fixedTrump = -1,
    this.teamPlay = false,
    required this.scoreMode,
    this.pointsRule = '',
    this.captureRule = '',
    required this.uiMode,
    this.targetScore = 0,
    this.rounds = 0,
    this.roundWinsTarget = 0,
    this.bidMin = 1,
    this.bidMax = 8,
    this.bidUnit = 'tricks',
    this.bidStyle = 'number',
    this.bowers = false,
    this.heartsPts = 1,
    this.queenSpadesPts = 13,
    this.tricksToWin = 7,
    this.aiFlavor = '',
  });
}

TrickConfig gameConfig() => const TrickConfig(
  gameId: 'qavextarneebpro',
  players: 4,
  deck: 'std52',
  handSize: 13,
  bidding: true,
  trumpMode: 'bid',
  teamPlay: true,
  scoreMode: 'tarneeb',
  uiMode: 'trick',
  targetScore: 41,
  bidMin: 7,
  bidMax: 13,
  bidUnit: 'tricks',
  bidStyle: 'number',
  aiFlavor: 'Majlis masters who bid tarneeb with desert-calm nerves.',
);

// ============================== engine ==============================

class _Snap {
  final List<List<TCard>> hands;
  final List<TCard> table;
  final List<TCard> stock;
  final List<List<TCard>> captured;
  final List<TrickPlay> trick;
  final List<int> bids;
  final List<int> tricksTaken;
  final List<int> trickPoints;
  final List<int> meldPts;
  final List<int> scopaCount;
  final List<int> pishtiCount;
  final List<List<TCard>> sevRows;
  final List<bool> sevStarted;
  final List<int> sevLow;
  final List<int> sevHigh;
  final List<int> matchScore;
  final List<int> bags;
  final int leader;
  final int turn;
  final int trump;
  final int bidWinner;
  final int bidTricks;
  final int roundNo;
  final int moves;
  final int score;
  final bool won;
  final String phase;
  final int currentBidder;
  final bool needTrumpPick;
  final int lastCapturer;
  final String statusLine;
  const _Snap({
    required this.hands,
    required this.table,
    required this.stock,
    required this.captured,
    required this.trick,
    required this.bids,
    required this.tricksTaken,
    required this.trickPoints,
    required this.meldPts,
    required this.scopaCount,
    required this.pishtiCount,
    required this.sevRows,
    required this.sevStarted,
    required this.sevLow,
    required this.sevHigh,
    required this.matchScore,
    required this.bags,
    required this.leader,
    required this.turn,
    required this.trump,
    required this.bidWinner,
    required this.bidTricks,
    required this.roundNo,
    required this.moves,
    required this.score,
    required this.won,
    required this.phase,
    required this.currentBidder,
    required this.needTrumpPick,
    required this.lastCapturer,
    required this.statusLine,
  });
}

class TrickEngine {
  final TrickConfig cfg;
  final int aiLevel; // 0 easy .. 3 expert
  int roundsOverride = 0;
  final _SeededRandom _aiRnd = _SeededRandom(1234567);

  List<int> matchScore = [];
  List<int> bags = [];
  List<List<TCard>> hands = [];
  List<TCard> table = [];
  List<TCard> stock = [];
  List<List<TCard>> captured = [];
  List<TrickPlay> trick = [];
  List<int> bids = [];
  List<int> tricksTaken = [];
  List<int> trickPoints = [];
  List<int> meldPts = [];
  List<int> scopaCount = [];
  List<int> pishtiCount = [];
  List<List<TCard>> sevRows = [];
  List<bool> sevStarted = [];
  List<int> sevLow = [];
  List<int> sevHigh = [];
  int leader = 0;
  int turn = 0;
  int trump = -1;
  int bidWinner = -1;
  int bidTricks = 0;
  int roundNo = 1;
  int moves = 0;
  int score = 0;
  bool won = false;
  String phase = 'bid'; // bid | play | done
  int currentBidder = -1;
  bool needTrumpPick = false;
  int lastCapturer = -1;
  String statusLine = '';
  final List<_Snap> _undo = [];

  TrickEngine(this.cfg, {this.aiLevel = 1});

  int get roundsTotal => roundsOverride > 0 ? roundsOverride : cfg.rounds;
  bool get isMatchOver => phase == 'done';
  bool get _lowWins =>
      cfg.scoreMode == 'avoid' || cfg.scoreMode == 'sevens';
  int teamOf(int seat) =>
      cfg.teamPlay && cfg.players == 4 ? seat % 2 : seat;
  int teamScore(int t) {
    int s = 0;
    for (int i = 0; i < cfg.players; i++) {
      if (teamOf(i) == t) s += matchScore[i];
    }
    return s;
  }
  int _partnerOf(int seat) => cfg.teamPlay && cfg.players == 4
      ? (seat + 2) % cfg.players
      : -1;
  String _seatName(int seat) => seat == 0 ? 'You' : 'Player ${seat + 1}';
  String _suitName(int s) =>
      const ['Spades', 'Hearts', 'Diamonds', 'Clubs'][s];
  String trumpLabel() => trump < 0 ? 'No trump' : _suitName(trump);

  // ---------------- match / round setup ----------------

  void newMatch({int? seed}) {
    matchScore = List.filled(cfg.players, 0);
    bags = List.filled(cfg.players, 0);
    roundNo = 1;
    moves = 0;
    won = false;
    _undo.clear();
    newRound(seed: seed);
  }

  void newRound({int? seed}) {
    final rng = seed == null ? null : _SeededRandom(seed);
    final deck = buildDeck(cfg.deck);
    if (rng == null) {
      deck.shuffle();
    } else {
      rng.shuffle(deck);
    }
    hands = List.generate(cfg.players, (_) => <TCard>[]);
    table = <TCard>[];
    stock = <TCard>[];
    captured = List.generate(cfg.players, (_) => <TCard>[]);
    trick = <TrickPlay>[];
    bids = List.filled(cfg.players, -1);
    tricksTaken = List.filled(cfg.players, 0);
    trickPoints = List.filled(cfg.players, 0);
    meldPts = List.filled(cfg.players, 0);
    scopaCount = List.filled(cfg.players, 0);
    pishtiCount = List.filled(cfg.players, 0);
    sevRows = List.generate(4, (_) => <TCard>[]);
    sevStarted = List.filled(4, false);
    sevLow = List.filled(4, 7);
    sevHigh = List.filled(4, 7);
    bidWinner = -1;
    bidTricks = 0;
    needTrumpPick = false;
    lastCapturer = -1;
    statusLine = '';
    _undo.clear();
    leader = (roundNo - 1) % cfg.players;
    turn = leader;

    if (cfg.uiMode == 'capture') {
      for (int i = 0; i < cfg.tableCards && deck.isNotEmpty; i++) {
        table.add(deck.removeLast());
      }
      for (int p = 0; p < cfg.players; p++) {
        for (int i = 0; i < cfg.handSize && deck.isNotEmpty; i++) {
          hands[p].add(deck.removeLast());
        }
      }
      stock = deck;
      trump = -1;
      phase = 'play';
    } else if (cfg.uiMode == 'sevens') {
      int p = 0;
      while (deck.isNotEmpty) {
        hands[p % cfg.players].add(deck.removeLast());
        p++;
      }
      trump = -1;
      phase = 'play';
    } else {
      for (int p = 0; p < cfg.players; p++) {
        for (int i = 0; i < cfg.handSize && deck.isNotEmpty; i++) {
          hands[p].add(deck.removeLast());
        }
      }
      stock = deck; // leftovers feed briscola-style redraws
      switch (cfg.trumpMode) {
        case 'fixed':
          trump = cfg.fixedTrump;
          break;
        case 'random':
          trump = rng == null ? _aiRnd.nextInt(4) : rng.nextInt(4);
          break;
        default:
          trump = -1;
      }
      if (cfg.bidding) {
        phase = 'bid';
        currentBidder = cfg.players > 1 ? 1 : 0;
      } else {
        phase = 'play';
      }
      _onTrumpSet();
    }
    _sortHands();
    _refreshScore();
  }

  void _sortHands() {
    for (final h in hands) {
      h.sort((a, b) {
        final ea = effectiveSuit(a);
        final eb = effectiveSuit(b);
        if (ea != eb) return ea.compareTo(eb);
        return b.rank.compareTo(a.rank);
      });
    }
  }

  void _onTrumpSet() {
    _scoreMeld();
  }

  /// Simplified pinochle meld, scored once trump is known.
  void _scoreMeld() {
    if (cfg.pointsRule != 'pinochle' || trump < 0) return;
    for (int p = 0; p < cfg.players; p++) {
      final hand = hands[p];
      bool has(int s, int r) =>
          hand.any((c) => c.suit == s && c.rank == r);
      bool allSuits(int r) =>
          has(0, r) && has(1, r) && has(2, r) && has(3, r);
      int m = 0;
      if (has(trump, 14) &&
          has(trump, 10) &&
          has(trump, 13) &&
          has(trump, 12) &&
          has(trump, 11)) {
        m += 15; // run
      } else if (has(trump, 13) && has(trump, 12)) {
        m += 4; // royal marriage
      }
      for (int s = 0; s < 4; s++) {
        if (s != trump && has(s, 13) && has(s, 12)) m += 2;
      }
      if (has(trump, 9)) m += 1; // dix
      if (allSuits(14)) m += 10;
      if (allSuits(13)) m += 8;
      if (allSuits(12)) m += 6;
      if (allSuits(11)) m += 4;
      if (has(0, 12) && has(2, 11)) m += 4; // pinochle
      meldPts[p] = m;
    }
  }

  // ---------------- bidding ----------------

  List<int> legalBids(int seat) {
    if (cfg.bidStyle == 'takeIt') return const [0, 1];
    final out = <int>[];
    for (int b = cfg.bidMin; b <= cfg.bidMax; b++) {
      out.add(b);
    }
    return out;
  }

  bool placeBid(int seat, int bid) {
    if (phase != 'bid' ||
        seat != currentBidder ||
        needTrumpPick ||
        isMatchOver) {
      return false;
    }
    if (!legalBids(seat).contains(bid)) return false;
    _pushUndo();
    bids[seat] = bid;
    moves++;
    if (cfg.bidStyle == 'takeIt' && bid == 1) {
      bidWinner = seat;
      bidTricks = 0;
      _finishBidding();
      return true;
    }
    int next = -1;
    for (int k = 1; k <= cfg.players; k++) {
      final s = (seat + k) % cfg.players;
      if (bids[s] < 0) {
        next = s;
        break;
      }
    }
    if (next < 0) {
      _finishBidding();
    } else {
      currentBidder = next;
    }
    return true;
  }

  void _finishBidding() {
    currentBidder = -1;
    if (cfg.bidStyle == 'takeIt') {
      if (bidWinner < 0) {
        bidWinner = cfg.players - 1; // everyone passed: last seat takes
      }
      bidTricks = 0;
    } else {
      int best = -1;
      int bestBid = -1;
      for (int s = 0; s < cfg.players; s++) {
        if (bids[s] > bestBid) {
          bestBid = bids[s];
          best = s;
        }
      }
      bidWinner = best;
      bidTricks = bestBid;
    }
    if (cfg.trumpMode == 'bid') {
      if (bidWinner == 0) {
        needTrumpPick = true;
        statusLine = 'You won the bid - name the trump suit.';
        return;
      }
      trump = _aiTrumpChoice(bidWinner);
      _onTrumpSet();
      statusLine =
          '${_seatName(bidWinner)} wins the bid and names ${_suitName(trump)}.';
    } else {
      statusLine =
          '${_seatName(bidWinner)} wins the bid with $bidTricks.';
    }
    _sortHands();
    phase = 'play';
    leader = bidWinner >= 0 ? bidWinner : 0;
    turn = leader;
  }

  void setTrump(int suit) {
    if (!needTrumpPick || suit < 0 || suit > 3) return;
    _pushUndo();
    trump = suit;
    needTrumpPick = false;
    _onTrumpSet();
    _sortHands();
    phase = 'play';
    leader = bidWinner >= 0 ? bidWinner : 0;
    turn = leader;
    statusLine = 'Trump is ${_suitName(trump)}.';
  }

  int _aiTrumpChoice(int seat) => _bestSuit(hands[seat]);

  int _bestSuit(List<TCard> hand) {
    int best = 0;
    int bestScore = -1;
    for (int s = 0; s < 4; s++) {
      final cards = hand.where((c) => c.suit == s).toList();
      int sc = cards.length * 10;
      for (final c in cards) {
        if (c.rank == 14 || c.rank == 1) {
          sc += 3;
        } else if (c.rank >= 12) {
          sc += 2;
        }
      }
      if (sc > bestScore) {
        bestScore = sc;
        best = s;
      }
    }
    return best;
  }

  // ---------------- trick mechanics ----------------

  int effectiveSuit(TCard c) {
    if (cfg.bowers && trump >= 0 && c.rank == 11) {
      if (c.suit == trump) return trump;
      if (_sameColor(c.suit, trump)) return trump;
    }
    return c.suit;
  }

  bool _sameColor(int a, int b) =>
      (a == 0 && b == 3) ||
      (a == 3 && b == 0) ||
      (a == 1 && b == 2) ||
      (a == 2 && b == 1);

  int _power(TCard c) {
    if (cfg.bowers && trump >= 0 && c.rank == 11) {
      if (c.suit == trump) return 500;
      if (_sameColor(c.suit, trump)) return 499;
    }
    if (trump >= 0 && effectiveSuit(c) == trump) return 100 + c.rank;
    return c.rank;
  }

  bool _beats(TCard c, TCard other) {
    final cs = effectiveSuit(c);
    final os = effectiveSuit(other);
    final ct = trump >= 0 && cs == trump;
    final ot = trump >= 0 && os == trump;
    if (ct && !ot) return true;
    if (!ct && ot) return false;
    if (cs != os) return false;
    return _power(c) > _power(other);
  }

  TrickPlay _currentBest() {
    int bi = 0;
    for (int i = 1; i < trick.length; i++) {
      if (_beats(trick[i].card, trick[bi].card)) bi = i;
    }
    return trick[bi];
  }

  int trickWinnerSeat() => _currentBest().seat;

  List<TCard> legalPlays(int seat) {
    final hand = hands[seat];
    if (trick.isEmpty) return List.of(hand);
    final led = effectiveSuit(trick[0].card);
    final follow =
        hand.where((c) => effectiveSuit(c) == led).toList();
    return follow.isEmpty ? List.of(hand) : follow;
  }

  bool playCard(int seat, TCard card) {
    if (phase != 'play' || isMatchOver || turn != seat) return false;
    if (cfg.uiMode != 'trick') return false;
    if (!hands[seat].contains(card)) return false;
    if (!legalPlays(seat).contains(card)) return false;
    _pushUndo();
    hands[seat].remove(card);
    trick.add(TrickPlay(seat, card));
    moves++;
    if (trick.length == cfg.players) {
      _resolveTrick();
    } else {
      turn = (seat + 1) % cfg.players;
    }
    return true;
  }

  void _resolveTrick() {
    final w = trickWinnerSeat();
    tricksTaken[w]++;
    for (final pl in trick) {
      captured[w].add(pl.card);
      trickPoints[w] += cardPoints(pl.card, cfg.pointsRule);
    }
    statusLine = '${_seatName(w)} takes the trick.';
    trick.clear();
    if (cfg.pointsRule == 'briscola' && stock.isNotEmpty) {
      for (int k = 0; k < cfg.players && stock.isNotEmpty; k++) {
        final s = (w + k) % cfg.players;
        hands[s].add(stock.removeLast());
      }
      _sortHands();
    }
    if (_roundComplete()) {
      endRound();
    } else {
      leader = w;
      turn = w;
    }
  }

  bool _roundComplete() {
    if (cfg.scoreMode == 'courtpiece') {
      for (int t = 0; t < 2; t++) {
        int tt = 0;
        for (int s = 0; s < cfg.players; s++) {
          if (teamOf(s) == t) tt += tricksTaken[s];
        }
        if (tt >= cfg.tricksToWin) return true;
      }
    }
    return hands.every((h) => h.isEmpty);
  }
  // ---------------- scoring ----------------

  void applyRoundScore() {
    switch (cfg.scoreMode) {
      case 'bid':
        for (int p = 0; p < cfg.players; p++) {
          matchScore[p] += tricksTaken[p] >= bids[p] ? bids[p] : -bids[p];
        }
        break;
      case 'courtpiece':
        for (int t = 0; t < 2; t++) {
          int tt = 0;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == t) tt += tricksTaken[s];
          }
          if (tt >= cfg.tricksToWin) {
            for (int s = 0; s < cfg.players; s++) {
              if (teamOf(s) == t) matchScore[s] += 1;
            }
          }
        }
        break;
      case 'avoid':
        {
          int total = 0;
          final pts = List.filled(cfg.players, 0);
          for (int p = 0; p < cfg.players; p++) {
            int q = 0;
            for (final c in captured[p]) {
              if (c.suit == 1) q += cfg.heartsPts;
              if (c.suit == 0 && c.rank == 12) q += cfg.queenSpadesPts;
            }
            pts[p] = q;
            total += q;
          }
          bool moon = false;
          for (int p = 0; p < cfg.players; p++) {
            if (total > 0 && pts[p] == total) moon = true;
          }
          if (moon) {
            for (int p = 0; p < cfg.players; p++) {
              matchScore[p] += pts[p] == total ? 0 : total;
            }
          } else {
            for (int p = 0; p < cfg.players; p++) {
              matchScore[p] += pts[p];
            }
          }
        }
        break;
      case 'contract':
        for (int p = 0; p < cfg.players; p++) {
          matchScore[p] += tricksTaken[p] == bids[p]
              ? 10 + 2 * bids[p]
              : tricksTaken[p];
        }
        break;
      case 'spades':
        for (int p = 0; p < cfg.players; p++) {
          if (tricksTaken[p] >= bids[p]) {
            final over = tricksTaken[p] - bids[p];
            matchScore[p] += 10 * bids[p] + over;
            bags[p] += over;
            if (bags[p] >= 10) {
              bags[p] -= 10;
              matchScore[p] -= 100;
            }
          } else {
            matchScore[p] -= 10 * bids[p];
          }
        }
        break;
      case 'euchre':
        {
          final mt = teamOf(bidWinner);
          int tt = 0;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) tt += tricksTaken[s];
          }
          int award = 0;
          bool makers = true;
          if (tt >= 5) {
            award = 2;
          } else if (tt >= 3) {
            award = 1;
          } else {
            award = 2;
            makers = false;
          }
          for (int s = 0; s < cfg.players; s++) {
            if ((teamOf(s) == mt) == makers) matchScore[s] += award;
          }
        }
        break;
      case 'bridge':
        {
          final mt = teamOf(bidWinner);
          for (int t = 0; t < 2; t++) {
            int tt = 0;
            int tb = 0;
            for (int s = 0; s < cfg.players; s++) {
              if (teamOf(s) == t) {
                tt += tricksTaken[s];
                if (bids[s] > tb) tb = bids[s];
              }
            }
            if (t == mt) {
              for (int s = 0; s < cfg.players; s++) {
                if (teamOf(s) == t) {
                  matchScore[s] +=
                      tt >= tb ? 25 * tt : -25 * (tb - tt);
                }
              }
            }
          }
        }
        break;
      case 'tarneeb':
        {
          final mt = teamOf(bidWinner);
          int tt = 0;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) tt += tricksTaken[s];
          }
          final delta = tt >= bidTricks ? bidTricks : -bidTricks;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) matchScore[s] += delta;
          }
        }
        break;
      case 'tricks':
        for (int p = 0; p < cfg.players; p++) {
          matchScore[p] += tricksTaken[p];
        }
        break;
      case 'points':
        _scorePointsRound();
        break;
      case 'capture':
        _scoreCaptureRound();
        break;
      case 'sevens':
        for (int p = 0; p < cfg.players; p++) {
          matchScore[p] += hands[p].length;
        }
        break;
    }
    _refreshScore();
  }

  void _scorePointsRound() {
    switch (cfg.pointsRule) {
      case 'twentynine':
        {
          final mt = teamOf(bidWinner);
          int tt = 0;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) tt += trickPoints[s];
          }
          final delta = tt >= bidTricks ? 1 : -1;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) matchScore[s] += delta;
          }
        }
        break;
      case 'skat':
        {
          final delta = trickPoints[bidWinner] >= bidTricks
              ? bidTricks
              : -2 * bidTricks;
          matchScore[bidWinner] += delta;
        }
        break;
      case 'pinochle':
        {
          final mt = teamOf(bidWinner);
          int tt = 0;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) tt += trickPoints[s] + meldPts[s];
          }
          final delta = tt >= bidTricks ? tt : -bidTricks;
          for (int s = 0; s < cfg.players; s++) {
            if (teamOf(s) == mt) matchScore[s] += delta;
          }
        }
        break;
      case 'briscola':
        {
          int w = 0;
          for (int s = 1; s < cfg.players; s++) {
            if (trickPoints[s] > trickPoints[w]) w = s;
          }
          matchScore[w] += 1;
        }
        break;
    }
  }

  int _argMax(List<int> xs) {
    int best = 0;
    for (int i = 1; i < xs.length; i++) {
      if (xs[i] > xs[best]) best = i;
    }
    int count = 0;
    for (final x in xs) {
      if (x == xs[best]) count++;
    }
    return count == 1 ? best : -1;
  }

  void _scoreCaptureRound() {
    if (cfg.captureRule == 'scopa') {
      final pts = List.filled(cfg.players, 0);
      final mostCards =
          _argMax(captured.map((l) => l.length).toList());
      final mostCoins = _argMax(captured
          .map((l) => l.where((c) => c.suit == 2).length)
          .toList());
      final mostSevens = _argMax(captured
          .map((l) => l.where((c) => c.rank == 7).length)
          .toList());
      if (mostCards >= 0) pts[mostCards]++;
      if (mostCoins >= 0) pts[mostCoins]++;
      if (mostSevens >= 0) pts[mostSevens]++;
      for (int p = 0; p < cfg.players; p++) {
        if (captured[p].any((c) => c.suit == 2 && c.rank == 7)) {
          pts[p]++; // settebello
        }
        pts[p] += scopaCount[p];
      }
      for (int p = 0; p < cfg.players; p++) {
        matchScore[p] += pts[p];
      }
    } else {
      // pishti
      final pts = List.filled(cfg.players, 0);
      for (int p = 0; p < cfg.players; p++) {
        for (final c in captured[p]) {
          if (c.rank == 14 || c.rank == 1) pts[p] += 1;
          if (c.rank == 11) pts[p] += 1;
          if (c.suit == 3 && c.rank == 2) pts[p] += 2;
          if (c.suit == 2 && c.rank == 10) pts[p] += 3;
        }
        pts[p] += pishtiCount[p] * 10;
      }
      final mc = _argMax(captured.map((l) => l.length).toList());
      if (mc >= 0) pts[mc] += 3;
      for (int p = 0; p < cfg.players; p++) {
        matchScore[p] += pts[p];
      }
    }
  }

  void endRound() {
    applyRoundScore();
    if (_matchDone()) {
      phase = 'done';
      won = playerWon;
      statusLine =
          won ? 'You win the match!' : '${_leaderName()} wins the match.';
    } else {
      roundNo++;
      newRound();
    }
    _refreshScore();
  }

  bool _matchDone() {
    if (cfg.roundWinsTarget > 0) {
      for (final s in matchScore) {
        if (s >= cfg.roundWinsTarget) return true;
      }
      return false;
    }
    if (roundsTotal > 0) return roundNo >= roundsTotal;
    if (_lowWins) {
      for (final s in matchScore) {
        if (s >= cfg.targetScore) return true;
      }
      return false;
    }
    for (final s in matchScore) {
      if (s >= cfg.targetScore) return true;
    }
    return false;
  }

  bool get playerWon {
    if (phase != 'done') return false;
    if (cfg.teamPlay) {
      final a = teamScore(0);
      final b = teamScore(1);
      return _lowWins ? a <= b : a >= b;
    }
    int bi = 0;
    for (int i = 1; i < matchScore.length; i++) {
      if (_lowWins
          ? matchScore[i] < matchScore[bi]
          : matchScore[i] > matchScore[bi]) {
        bi = i;
      }
    }
    return bi == 0;
  }

  String _leaderName() {
    if (cfg.teamPlay) {
      return teamScore(0) >= teamScore(1) ? 'Your team' : 'The rivals';
    }
    int bi = 0;
    for (int i = 1; i < matchScore.length; i++) {
      if (_lowWins
          ? matchScore[i] < matchScore[bi]
          : matchScore[i] > matchScore[bi]) {
        bi = i;
      }
    }
    return _seatName(bi);
  }

  void _refreshScore() {
    score = cfg.teamPlay ? teamScore(0) : matchScore[0];
  }

  // ---------------- capture games (scopa / pishti) ----------------

  int scopaValue(TCard c) {
    if (c.rank <= 7) return c.rank;
    if (c.rank == 11) return 8;
    if (c.rank == 12) return 9;
    return 10;
  }

  List<List<TCard>> captureOptions(TCard card) {
    final v = scopaValue(card);
    final res = <List<TCard>>[];
    final n = table.length;
    if (n > 16) return res;
    for (int mask = 1; mask < (1 << n); mask++) {
      int sum = 0;
      final sub = <TCard>[];
      for (int i = 0; i < n; i++) {
        if ((mask & (1 << i)) != 0) {
          sum += scopaValue(table[i]);
          sub.add(table[i]);
        }
      }
      if (sum == v) res.add(sub);
    }
    return res;
  }

  /// Returns 'captured', 'tabled', 'choose' or 'error'.
  String playCapture(int seat, TCard card) {
    if (phase != 'play' || isMatchOver || turn != seat) return 'error';
    if (cfg.uiMode != 'capture') return 'error';
    if (!hands[seat].contains(card)) return 'error';
    _pushUndo();
    hands[seat].remove(card);
    moves++;
    String result;
    if (cfg.captureRule == 'scopa') {
      final opts = captureOptions(card);
      if (opts.isEmpty) {
        table.add(card);
        result = 'tabled';
      } else if (opts.length == 1) {
        _takeCapture(seat, card, opts[0]);
        result = 'captured';
      } else {
        hands[seat].add(card);
        _sortHands();
        _undo.removeLast();
        return 'choose';
      }
    } else {
      if (table.isNotEmpty &&
          (card.rank == 11 || card.rank == table.last.rank)) {
        final swept = List<TCard>.of(table);
        final single = table.length == 1;
        table.clear();
        captured[seat].addAll(swept);
        captured[seat].add(card);
        if (single) pishtiCount[seat]++;
        lastCapturer = seat;
        statusLine = single
            ? '${_seatName(seat)} scores a PISHTI!'
            : '${_seatName(seat)} sweeps ${swept.length + 1} cards.';
        result = 'captured';
      } else {
        table.add(card);
        result = 'tabled';
      }
    }
    _afterCapturePlay(seat);
    return result;
  }

  bool playCaptureSel(int seat, TCard card, List<TCard> selection) {
    if (phase != 'play' || isMatchOver || turn != seat) return false;
    if (cfg.uiMode != 'capture') return false;
    if (!hands[seat].contains(card)) return false;
    final opts = captureOptions(card);
    final ok = opts.any((o) =>
        o.length == selection.length &&
        selection.every((c) => o.contains(c)));
    if (!ok) return false;
    _pushUndo();
    hands[seat].remove(card);
    moves++;
    _takeCapture(seat, card, selection);
    _afterCapturePlay(seat);
    return true;
  }

  void _takeCapture(int seat, TCard card, List<TCard> sub) {
    for (final c in sub) {
      table.remove(c);
    }
    captured[seat].addAll(sub);
    captured[seat].add(card);
    lastCapturer = seat;
    if (table.isEmpty && !_captureRoundOver()) {
      scopaCount[seat]++;
      statusLine = '${_seatName(seat)} scores a SCOPA!';
    } else {
      statusLine =
          '${_seatName(seat)} captures ${sub.length + 1} cards.';
    }
  }

  bool _captureRoundOver() {
    if (!hands.every((h) => h.isEmpty)) return false;
    return stock.length < cfg.players * cfg.handSize;
  }

  void _afterCapturePlay(int seat) {
    if (hands.every((h) => h.isEmpty)) {
      if (stock.length >= cfg.players * cfg.handSize) {
        for (int p = 0; p < cfg.players; p++) {
          for (int i = 0; i < cfg.handSize; i++) {
            hands[p].add(stock.removeLast());
          }
        }
        _sortHands();
      } else {
        if (table.isNotEmpty && lastCapturer >= 0) {
          captured[lastCapturer].addAll(table);
          table.clear();
        }
        endRound();
        return;
      }
    }
    turn = (seat + 1) % cfg.players;
  }

  // ---------------- sevens ----------------

  List<TCard> sevensLegal(int seat) {
    final out = <TCard>[];
    for (final c in hands[seat]) {
      if (!sevStarted[c.suit]) {
        if (c.rank == 7) out.add(c);
      } else if (c.rank == sevLow[c.suit] - 1 ||
          c.rank == sevHigh[c.suit] + 1) {
        out.add(c);
      }
    }
    return out;
  }

  bool playSevens(int seat, TCard card) {
    if (phase != 'play' || isMatchOver || turn != seat) return false;
    if (cfg.uiMode != 'sevens') return false;
    if (!sevensLegal(seat).contains(card)) return false;
    _pushUndo();
    hands[seat].remove(card);
    moves++;
    final s = card.suit;
    if (!sevStarted[s]) {
      sevStarted[s] = true;
      sevLow[s] = 7;
      sevHigh[s] = 7;
      sevRows[s].add(card);
    } else if (card.rank == sevLow[s] - 1) {
      sevLow[s] = card.rank;
      sevRows[s].insert(0, card);
    } else {
      sevHigh[s] = card.rank;
      sevRows[s].add(card);
    }
    statusLine = '${_seatName(seat)} plays $card.';
    if (hands[seat].isEmpty) {
      endRound();
      return true;
    }
    turn = (seat + 1) % cfg.players;
    return true;
  }

  bool passSevens(int seat) {
    if (phase != 'play' || isMatchOver || turn != seat) return false;
    if (cfg.uiMode != 'sevens') return false;
    if (sevensLegal(seat).isNotEmpty) return false;
    _pushUndo();
    moves++;
    statusLine = '${_seatName(seat)} passes.';
    turn = (seat + 1) % cfg.players;
    return true;
  }

  // ---------------- AI ----------------

  void aiBid(int seat) {
    if (phase != 'bid' ||
        seat != currentBidder ||
        needTrumpPick ||
        isMatchOver) {
      return;
    }
    if (cfg.bidStyle == 'takeIt') {
      final hand = hands[seat];
      final best = _bestSuit(hand);
      final count = hand.where((c) => c.suit == best).length;
      bool take;
      if (aiLevel == 0) {
        take = _aiRnd.nextInt(100) < 45;
      } else if (aiLevel == 1) {
        take = count >= 3;
      } else {
        take = count >= 2;
      }
      placeBid(seat, take ? 1 : 0);
      return;
    }
    int est =
        cfg.bidUnit == 'points' ? _aiBidPoints(seat) : _aiBidTricks(seat);
    if (aiLevel == 0) {
      est += _aiRnd.nextInt(5) - 2;
    } else if (aiLevel == 1) {
      est += _aiRnd.nextInt(3) - 1;
    }
    est = est.clamp(cfg.bidMin, cfg.bidMax);
    placeBid(seat, est);
  }

  int _aiBidTricks(int seat) {
    final hand = hands[seat];
    final tr = trump >= 0 ? trump : _bestSuit(hand);
    double e = 0;
    for (int s = 0; s < 4; s++) {
      final cards = hand
          .where((c) => effectiveSuit(c) == s)
          .toList()
        ..sort((a, b) => b.rank.compareTo(a.rank));
      for (int i = 0; i < cards.length; i++) {
        final r = cards[i].rank;
        final ace = r == 14 || r == 1;
        if (ace) {
          e += 1.0;
        } else if (r == 13) {
          e += i == 0 ? 0.85 : 0.5;
        } else if (r == 12) {
          e += i <= 1 ? 0.4 : 0.15;
        }
      }
      if (s == tr) e += 0.3 * cards.length;
    }
    return e.round().clamp(cfg.bidMin, cfg.bidMax);
  }

  int _aiBidPoints(int seat) {
    int pts = 0;
    for (final c in hands[seat]) {
      pts += cardPoints(c, cfg.pointsRule);
    }
    int bid;
    switch (cfg.pointsRule) {
      case 'twentynine':
        bid = pts * 2;
        break;
      case 'skat':
        bid = pts * 2;
        break;
      case 'pinochle':
        bid = pts + 15;
        break;
      default:
        bid = pts;
    }
    return bid.clamp(cfg.bidMin, cfg.bidMax);
  }

  void aiPlay(int seat) {
    if (phase != 'play' || turn != seat || isMatchOver) return;
    if (cfg.uiMode != 'trick') return;
    playCard(seat, aiChooseCard(seat));
  }

  TCard aiChooseCard(int seat) {
    final legal = legalPlays(seat);
    if (legal.length == 1) return legal[0];
    if (aiLevel == 0) return legal[_aiRnd.nextInt(legal.length)];
    if (trick.isEmpty) return _aiLead(legal);
    return _aiFollow(seat, legal);
  }

  TCard _aiLead(List<TCard> legal) {
    if (aiLevel == 1) return legal[_aiRnd.nextInt(legal.length)];
    final pool = trump >= 0
        ? legal.where((c) => effectiveSuit(c) != trump).toList()
        : legal;
    final use = pool.isEmpty ? legal : pool;
    final bySuit = <int, List<TCard>>{};
    for (final c in use) {
      bySuit.putIfAbsent(effectiveSuit(c), () => <TCard>[]).add(c);
    }
    List<TCard> bestGroup = use;
    int bestLen = -1;
    int bestTop = -1;
    bySuit.forEach((s, g) {
      g.sort((a, b) => _power(b).compareTo(_power(a)));
      if (g.length > bestLen ||
          (g.length == bestLen && _power(g[0]) > bestTop)) {
        bestLen = g.length;
        bestTop = _power(g[0]);
        bestGroup = g;
      }
    });
    return bestGroup[0];
  }

  TCard _aiFollow(int seat, List<TCard> legal) {
    TCard lowest(List<TCard> l) {
      TCard m = l[0];
      for (final c in l) {
        if (_power(c) < _power(m)) m = c;
      }
      return m;
    }

    final best = _currentBest();
    final partner = _partnerOf(seat);
    if (partner >= 0 && best.seat == partner) return lowest(legal);
    final winners =
        legal.where((c) => _beats(c, best.card)).toList();
    if (winners.isNotEmpty) {
      if (aiLevel == 1 && _aiRnd.nextBool()) return lowest(legal);
      return lowest(winners);
    }
    return lowest(legal);
  }

  void aiCapture(int seat) {
    if (phase != 'play' || turn != seat || isMatchOver) return;
    if (cfg.uiMode != 'capture') return;
    final hand = hands[seat];
    if (hand.isEmpty) return;
    if (cfg.captureRule == 'scopa') {
      TCard? pick;
      List<TCard> pickSub = [];
      for (final c in hand) {
        final opts = captureOptions(c);
        if (opts.isNotEmpty) {
          opts.sort((a, b) => b.length.compareTo(a.length));
          if (pick == null || opts[0].length > pickSub.length) {
            pick = c;
            pickSub = opts[0];
          }
        }
      }
      if (pick != null) {
        playCaptureSel(seat, pick, pickSub);
        return;
      }
      TCard low = hand[0];
      for (final c in hand) {
        if (scopaValue(c) < scopaValue(low)) low = c;
      }
      playCapture(seat, low);
    } else {
      for (final c in hand) {
        if (table.isNotEmpty &&
            c.rank != 11 &&
            c.rank == table.last.rank) {
          playCapture(seat, c);
          return;
        }
      }
      for (final c in hand) {
        if (c.rank == 11 && table.isNotEmpty) {
          playCapture(seat, c);
          return;
        }
      }
      TCard low = hand[0];
      for (final c in hand) {
        if (c.rank != 11 && c.rank < low.rank) low = c;
      }
      if (low.rank == 11) low = hand[0];
      playCapture(seat, low);
    }
  }

  void aiSevens(int seat) {
    if (phase != 'play' || turn != seat || isMatchOver) return;
    if (cfg.uiMode != 'sevens') return;
    final legal = sevensLegal(seat);
    if (legal.isEmpty) {
      passSevens(seat);
      return;
    }
    legal.sort((a, b) {
      int k(TCard c) => c.rank == 7 ? 0 : 1;
      final ka = k(a);
      final kb = k(b);
      if (ka != kb) return ka.compareTo(kb);
      return a.rank.compareTo(b.rank);
    });
    playSevens(seat, legal[0]);
  }

  // ---------------- hints ----------------

  TCard? hintCard() {
    if (phase != 'play' || turn != 0 || isMatchOver) return null;
    if (cfg.uiMode == 'trick') return aiChooseCard(0);
    if (cfg.uiMode == 'sevens') {
      final l = sevensLegal(0);
      return l.isEmpty ? null : l[0];
    }
    for (final c in hands[0]) {
      if (cfg.captureRule == 'scopa' && captureOptions(c).isNotEmpty) {
        return c;
      }
      if (cfg.captureRule == 'pishti' &&
          table.isNotEmpty &&
          (c.rank == 11 || c.rank == table.last.rank)) return c;
    }
    return hands[0].isEmpty ? null : hands[0][0];
  }

  String hintText() {
    if (phase == 'bid') {
      if (needTrumpPick) {
        return 'You won the bid - choose the trump suit.';
      }
      if (cfg.bidStyle == 'takeIt') {
        return 'Take if ${_suitName(_bestSuit(hands[0]))} looks strong, else pass.';
      }
      final s = cfg.bidUnit == 'points'
          ? _aiBidPoints(0)
          : _aiBidTricks(0);
      return 'Bid around $s ${cfg.bidUnit} based on your hand.';
    }
    if (phase != 'play') return '';
    final c = hintCard();
    if (c == null) return 'No move available right now.';
    if (cfg.uiMode == 'sevens') return 'Try playing $c.';
    if (cfg.uiMode == 'capture') {
      if (cfg.captureRule == 'scopa') {
        final opts = captureOptions(c);
        if (opts.isNotEmpty) {
          return 'Play $c to capture ${opts[0].length} table card(s).';
        }
        return 'No capture with $c - it goes to the table.';
      }
      return 'Play $c.';
    }
    if (trick.isEmpty) return 'Lead with $c.';
    return 'Play $c.';
  }

  // ---------------- undo ----------------

  void _pushUndo() {
    _undo.add(_Snap(
      hands: hands.map((h) => List<TCard>.of(h)).toList(),
      table: List.of(table),
      stock: List.of(stock),
      captured: captured.map((h) => List<TCard>.of(h)).toList(),
      trick: List.of(trick),
      bids: List.of(bids),
      tricksTaken: List.of(tricksTaken),
      trickPoints: List.of(trickPoints),
      meldPts: List.of(meldPts),
      scopaCount: List.of(scopaCount),
      pishtiCount: List.of(pishtiCount),
      sevRows: sevRows.map((h) => List<TCard>.of(h)).toList(),
      sevStarted: List.of(sevStarted),
      sevLow: List.of(sevLow),
      sevHigh: List.of(sevHigh),
      matchScore: List.of(matchScore),
      bags: List.of(bags),
      leader: leader,
      turn: turn,
      trump: trump,
      bidWinner: bidWinner,
      bidTricks: bidTricks,
      roundNo: roundNo,
      moves: moves,
      score: score,
      won: won,
      phase: phase,
      currentBidder: currentBidder,
      needTrumpPick: needTrumpPick,
      lastCapturer: lastCapturer,
      statusLine: statusLine,
    ));
    if (_undo.length > 300) _undo.removeAt(0);
  }

  bool get canUndo => _undo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    hands = s.hands;
    table = s.table;
    stock = s.stock;
    captured = s.captured;
    trick = s.trick;
    bids = s.bids;
    tricksTaken = s.tricksTaken;
    trickPoints = s.trickPoints;
    meldPts = s.meldPts;
    scopaCount = s.scopaCount;
    pishtiCount = s.pishtiCount;
    sevRows = s.sevRows;
    sevStarted = s.sevStarted;
    sevLow = s.sevLow;
    sevHigh = s.sevHigh;
    matchScore = s.matchScore;
    bags = s.bags;
    leader = s.leader;
    turn = s.turn;
    trump = s.trump;
    bidWinner = s.bidWinner;
    bidTricks = s.bidTricks;
    roundNo = s.roundNo;
    moves = s.moves;
    score = s.score;
    won = false;
    phase = s.phase;
    currentBidder = s.currentBidder;
    needTrumpPick = s.needTrumpPick;
    lastCapturer = s.lastCapturer;
    statusLine = s.statusLine;
    _refreshScore();
  }
}
