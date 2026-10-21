import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qavextarneebpro/core/app_state.dart';
import 'package:qavextarneebpro/core/sound.dart';
import 'package:qavextarneebpro/game/logic.dart';
import 'package:qavextarneebpro/game/cards_ui.dart';
import 'package:qavextarneebpro/screens/mode_select.dart';

class GameScreen extends StatefulWidget {
  final GameModeDef mode;
  const GameScreen({super.key, required this.mode});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _rivalNames = <String>['Layal', 'Karim', 'Nadia'];
  late TrickEngine _e;
  Timer? _timer;
  int _elapsed = 0;
  int _timeLeft = 0;
  bool _over = false;
  bool _won = false;
  bool _paused = false;
  bool _recorded = false;
  String _message = '';
  int _hints = 0;
  int _undos = 0;
  int _bidVal = 1;
  int _ladderRung = 1;
  TCard? _selCard;
  final Set<TCard> _selTable = {};
  TCard? _hintGlow;

  bool get _isTimed => widget.mode.id == 'timed';
  bool get _isDaily => widget.mode.id == 'daily';
  bool get _isZen => widget.mode.id == 'zen';
  bool get _isKids => widget.mode.id == 'kids';
  bool get _isPractice => widget.mode.id == 'practice';
  bool get _isLadder => widget.mode.id == 'ladder';
  bool get _isTournament => widget.mode.id == 'tournament';

  int _aiForMode() {
    if (_isKids || _isPractice) return 0;
    if (_isLadder) return 3;
    if (_isDaily || _isTimed || _isTournament) return 2;
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _e = TrickEngine(gameConfig(), aiLevel: _aiForMode());
    if (_isTournament) _e.roundsOverride = 5;
    _e.newMatch(seed: _initialSeed());
    _bidVal = _e.cfg.bidMin;
    _loadRung();
    _startTimer();
    _pumpAI();
    if (_isPractice) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && !_over && !_paused) _doHint(auto: true);
      });
    }
  }

  Future<void> _loadRung() async {
    final prefs = await SharedPreferences.getInstance();
    final r = prefs.getInt('qavextarneebpro_ladder_rung') ?? 1;
    if (mounted) setState(() => _ladderRung = r.clamp(1, 8));
  }

  int _initialSeed() {
    if (_isDaily) {
      final n = DateTime.now();
      return n.year * 10000 + n.month * 100 + n.day;
    }
    return DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  }

  void _startTimer() {
    _timer?.cancel();
    if (_isTimed) _timeLeft = 600;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _over) return;
      _elapsed++;
      if (_isTimed) {
        _timeLeft--;
        if (_timeLeft <= 0) {
          _timeLeft = 0;
          _onTimeUp();
          return;
        }
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _rivalName(int seat) {
    final base = _rivalNames[(seat - 1) % _rivalNames.length];
    if (_e.cfg.teamPlay && seat == 2) return '$base (Partner)';
    return base;
  }

  void _flash(String msg) {
    setState(() => _message = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _message == msg) setState(() => _message = '');
    });
  }

  // ---------------- AI pump ----------------

  void _pumpAI() {
    if (_over || _paused || !mounted) return;
    if (_e.isMatchOver) {
      _onMatchEnd();
      return;
    }
    final needsAI = (_e.phase == 'bid' &&
            _e.currentBidder > 0 &&
            !_e.needTrumpPick) ||
        (_e.phase == 'play' && _e.turn != 0);
    if (!needsAI) {
      setState(() {});
      return;
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _over || _paused || _e.isMatchOver) return;
      bool acted = false;
      if (_e.phase == 'bid' &&
          _e.currentBidder > 0 &&
          !_e.needTrumpPick) {
        _e.aiBid(_e.currentBidder);
        acted = true;
      } else if (_e.phase == 'play' && _e.turn != 0) {
        final s = _e.turn;
        if (_e.cfg.uiMode == 'trick') {
          _e.aiPlay(s);
        } else if (_e.cfg.uiMode == 'capture') {
          _e.aiCapture(s);
        } else {
          _e.aiSevens(s);
        }
        acted = true;
      }
      if (acted) {
        SoundService.I.play('tap');
        setState(() {});
        _pumpAI();
      }
    });
  }

  // ---------------- human actions ----------------

  void _humanBid(int bid) {
    if (_e.placeBid(0, bid)) {
      SoundService.I.play('click');
      setState(() {});
      _pumpAI();
    } else {
      SoundService.I.play('error');
    }
  }

  void _humanTrump(int suit) {
    _e.setTrump(suit);
    SoundService.I.play('success');
    setState(() {});
    _pumpAI();
  }

  void _tapHandCard(TCard card) {
    if (_over || _paused || _e.isMatchOver) return;
    if (_e.phase != 'play' || _e.turn != 0) return;
    if (_e.cfg.uiMode == 'trick') {
      if (_e.playCard(0, card)) {
        SoundService.I.play('pop');
        _hintGlow = null;
        setState(() {});
        _pumpAI();
      } else {
        SoundService.I.play('error');
        _flash('That card is not legal now - follow suit if you can.');
      }
    } else if (_e.cfg.uiMode == 'capture') {
      _tapCaptureHand(card);
    } else {
      if (_e.playSevens(0, card)) {
        SoundService.I.play('pop');
        _hintGlow = null;
        setState(() {});
        _pumpAI();
      } else {
        SoundService.I.play('error');
      }
    }
  }

  void _tapCaptureHand(TCard card) {
    if (_e.cfg.captureRule == 'pishti') {
      final r = _e.playCapture(0, card);
      if (r == 'error') {
        SoundService.I.play('error');
        return;
      }
      SoundService.I.play(r == 'captured' ? 'success' : 'tap');
      setState(() {});
      _pumpAI();
      return;
    }
    setState(() {
      if (_selCard == card) {
        _selCard = null;
        _selTable.clear();
      } else {
        _selCard = card;
        _selTable.clear();
      }
    });
    SoundService.I.play('tap');
  }

  void _tapTableCard(TCard card) {
    if (_selCard == null) return;
    setState(() {
      if (_selTable.contains(card)) {
        _selTable.remove(card);
      } else {
        _selTable.add(card);
      }
    });
    SoundService.I.play('tap');
  }

  void _confirmCapture() {
    final c = _selCard;
    if (c == null) return;
    if (_e.playCaptureSel(0, c, _selTable.toList())) {
      SoundService.I.play('success');
      setState(() {
        _selCard = null;
        _selTable.clear();
      });
      _pumpAI();
    } else {
      SoundService.I.play('error');
      _flash('Those cards do not add up to your card.');
    }
  }

  void _tableIt() {
    final c = _selCard;
    if (c == null) return;
    final r = _e.playCapture(0, c);
    if (r == 'choose') {
      _flash('Several captures are possible - pick the table cards.');
      return;
    }
    SoundService.I.play('tap');
    setState(() {
      _selCard = null;
      _selTable.clear();
    });
    _pumpAI();
  }

  void _doHint({bool auto = false}) {
    if (_over || _paused || _e.isMatchOver) return;
    final c = _e.hintCard();
    setState(() {
      _hintGlow = c;
      _message = _e.hintText();
    });
    if (!auto) {
      _hints++;
      AppScope.of(context).addCounter('hints_used', 1);
      SoundService.I.play('click');
    }
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _hintGlow == c) setState(() => _hintGlow = null);
    });
  }

  void _doUndo() {
    if (!_e.canUndo || _over || _paused || _e.phase != 'play') return;
    _e.undo();
    _undos++;
    AppScope.of(context).addCounter('undos_game', 1);
    SoundService.I.play('click');
    setState(() {
      _hintGlow = null;
      _selCard = null;
      _selTable.clear();
    });
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _e = TrickEngine(gameConfig(), aiLevel: _aiForMode());
      if (_isTournament) _e.roundsOverride = 5;
      _e.newMatch(seed: _initialSeed());
      _elapsed = 0;
      _over = false;
      _won = false;
      _paused = false;
      _recorded = false;
      _message = '';
      _hints = 0;
      _undos = 0;
      _selCard = null;
      _selTable.clear();
      _hintGlow = null;
      _bidVal = _e.cfg.bidMin;
    });
    SoundService.I.play('click');
    _startTimer();
    _pumpAI();
  }

  // ---------------- match end ----------------

  Future<void> _onMatchEnd() async {
    if (_recorded) return;
    _recorded = true;
    _over = true;
    _won = _e.won;
    _timer?.cancel();
    final app = AppScope.of(context);
    final sc = _e.score < 0 ? 0 : _e.score;
    await app.recordGame(mode: widget.mode.id, score: sc, won: _won);
    if (_won) {
      app.addCounter('nohint_wins', _hints == 0 ? 1 : 0);
      app.addCounter('fast_wins', _elapsed < 300 ? 1 : 0);
      app.addCounter(
          'flawless_wins', _hints == 0 && _undos == 0 ? 1 : 0);
    }
    if (_isDaily) {
      app.addCounter('daily_played', 1);
      if (_won) await app.touchDaily();
    }
    if (_isTimed && _won) app.addCounter('timed_wins', 1);
    if (_isZen) app.addCounter('zen_games', 1);
    if (_isKids) app.addCounter('kids_games', 1);
    if (_isPractice) app.addCounter('practice_games', 1);
    if (_isLadder && _won && _ladderRung < 8) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('qavextarneebpro_ladder_rung', _ladderRung + 1);
    }
    SoundService.I.play(_won ? 'win' : 'lose');
    if (mounted) setState(() {});
  }

  void _onTimeUp() {
    if (_over || _recorded) return;
    _flash('Time is up!');
    _onMatchEnd();
  }

  // ---------------- widgets ----------------

  Widget _chip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: QCardColors.gold),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _panel(Widget child) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QCardColors.gold.withOpacity(0.6)),
      ),
      child: child,
    );
  }

  Widget _scoreBar() {
    final c = _e.cfg;
    String progress;
    if (_e.roundsTotal > 0) {
      progress = 'Round ${_e.roundNo}/${_e.roundsTotal}';
    } else if (c.roundWinsTarget > 0) {
      progress = 'First to ${c.roundWinsTarget} rounds';
    } else {
      progress = 'Target ${c.targetScore}';
    }
    final chips = <Widget>[];
    if (c.teamPlay) {
      chips.add(_chip('You + Partner: ${_e.teamScore(0)}', Icons.group));
      chips.add(_chip('Rivals: ${_e.teamScore(1)}', Icons.groups));
    } else {
      chips.add(_chip('You: ${_e.matchScore[0]}', Icons.person));
      for (int s = 1; s < c.players; s++) {
        chips.add(_chip(
            '${_rivalName(s)}: ${_e.matchScore[s]}', Icons.person_outline));
      }
    }
    chips.add(_chip(progress, Icons.flag));
    if (_isLadder) chips.add(_chip('Rung $_ladderRung', Icons.trending_up));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: chips),
    );
  }

  Widget _statusRow() {
    String clock;
    if (_isTimed) {
      final m = _timeLeft ~/ 60;
      final s = _timeLeft % 60;
      clock =
          '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else if (_isDaily) {
      final n = DateTime.now();
      clock =
          '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    } else if (_isZen) {
      clock = 'Zen';
    } else {
      final m = _elapsed ~/ 60;
      final s = _elapsed % 60;
      clock =
          '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final turnText = _e.phase == 'bid'
        ? (_e.needTrumpPick ? 'Name the trump' : 'Bidding...')
        : (_e.turn == 0
            ? 'Your turn'
            : "${_rivalName(_e.turn)}'s turn");
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          _chip(_e.trumpLabel(), Icons.style),
          _chip(clock, _isTimed ? Icons.timer : Icons.schedule),
          _chip(turnText, Icons.touch_app),
        ],
      ),
    );
  }

  Widget _kidsBanner() {
    if (!_isKids) return const SizedBox.shrink();
    return _panel(
      Row(
        children: [
          const Icon(Icons.child_care, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Bid 7 or more only when your longest suit can carry the team. Only the bidding team scores.',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _card(TCard c, double w,
      {bool dimmed = false,
      bool selected = false,
      void Function()? onTap}) {
    final face = QCardFace(
        rank: c.rankLabel,
        suit: c.suitChar,
        width: w,
        dimmed: dimmed,
        selected: selected);
    if (onTap == null) return face;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(3),
        constraints:
            const BoxConstraints(minWidth: 48, minHeight: 48),
        child: face,
      ),
    );
  }

  Widget _rivalPanel(int seat, double cw) {
    final n = _e.hands[seat].length;
    final info = <String>[];
    if (_e.cfg.bidding && _e.bids[seat] >= 0) {
      info.add('bid ${_e.bids[seat]}');
    }
    if (_e.cfg.uiMode == 'trick') info.add('won ${_e.tricksTaken[seat]}');
    if (_e.cfg.uiMode == 'capture') {
      info.add('got ${_e.captured[seat].length}');
    }
    if (_e.cfg.uiMode == 'sevens') info.add('left $n');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_rivalName(seat),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        if (info.isNotEmpty)
          Text(info.join('  '),
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75), fontSize: 11)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < (n > 3 ? 3 : n); i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: QCardBack(width: cw * 0.42),
              ),
            const SizedBox(width: 4),
            Text('x$n',
                style:
                    const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _trickCards(double cw) {
    if (_e.trick.isEmpty) {
      return QCardSlot(
        width: cw,
        glyph: _e.phase == 'play' && _e.turn == 0 ? 'YOU' : '...',
        highlight: _e.phase == 'play' && _e.turn == 0 && !_over,
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final pl in _e.trick)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QCardFace(
                  rank: pl.card.rankLabel,
                  suit: pl.card.suitChar,
                  width: cw),
              const SizedBox(height: 2),
              Text(pl.seat == 0 ? 'You' : _rivalName(pl.seat),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 11)),
            ],
          ),
      ],
    );
  }

  Widget _tableArea(double cw) {
    final ui = _e.cfg.uiMode;
    if (ui == 'capture') return _captureTable(cw);
    if (ui == 'sevens') return _sevensTable(cw);
    return _trickTable(cw);
  }

  Widget _trickTable(double cw) {
    final p = _e.cfg.players;
    final trickView = Expanded(child: Center(child: _trickCards(cw)));
    final List<Widget> rows;
    if (p == 2) {
      rows = [_rivalPanel(1, cw), trickView];
    } else if (p == 3) {
      rows = [
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_rivalPanel(1, cw), _rivalPanel(2, cw)]),
        trickView,
      ];
    } else {
      rows = [
        _rivalPanel(2, cw),
        const SizedBox(height: 4),
        Row(children: [
          _rivalPanel(1, cw),
          trickView,
          _rivalPanel(3, cw)
        ]),
      ];
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: rows),
    );
  }

  Widget _rivalStrip() {
    return Wrap(
      spacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (int s = 1; s < _e.cfg.players; s++)
          Text(
              '${_rivalName(s)}: ${_e.matchScore[s]} (pile ${_e.captured[s].length})',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  Widget _captureTable(double cw) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          _rivalStrip(),
          const SizedBox(height: 4),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final c in _e.table)
                      _card(c, cw * 0.78,
                          selected: _selTable.contains(c),
                          onTap: _selCard == null
                              ? null
                              : () => _tapTableCard(c)),
                    if (_e.table.isEmpty)
                      QCardSlot(
                          width: cw * 0.78,
                          glyph: 'EMPTY',
                          highlight: false),
                  ],
                ),
              ),
            ),
          ),
          Text(
              'Table ${_e.table.length} - Stock ${_e.stock.length} - Your pile ${_e.captured[0].length}',
              style: const TextStyle(color: Colors.white, fontSize: 12)),
          if (_selCard != null && _e.cfg.captureRule == 'scopa')
            _captureConfirmBar(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _captureConfirmBar() {
    final c = _selCard!;
    int sum = 0;
    for (final t in _selTable) {
      sum += _e.scopaValue(t);
    }
    final need = _e.scopaValue(c);
    final ok = _selTable.isNotEmpty && sum == need;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Capture $sum / $need',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          ElevatedButton(
            onPressed: ok ? _confirmCapture : null,
            child: const Text('CAPTURE'),
          ),
          OutlinedButton(
            onPressed: _tableIt,
            child: const Text('Table it'),
          ),
        ],
      ),
    );
  }

  Widget _sevensTable(double cw) {
    final w = cw * 0.52;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          _rivalStrip(),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int s = 0; s < 4; s++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            const [
                              '\u2660',
                              '\u2665',
                              '\u2666',
                              '\u2663'
                            ][s],
                            style: TextStyle(
                              fontSize: 22,
                              color: (s == 1 || s == 2)
                                  ? const Color(0xFFE06060)
                                  : Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final c in _e.sevRows[s])
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 2),
                                    child: QCardFace(
                                        rank: c.rankLabel,
                                        suit: c.suitChar,
                                        width: w),
                                  ),
                                if (!_e.sevStarted[s])
                                  QCardSlot(
                                      width: w,
                                      glyph: '7',
                                      highlight: _e.turn == 0 &&
                                          !_over &&
                                          _e.phase == 'play'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_e.phase == 'play' &&
              _e.turn == 0 &&
              _e.sevensLegal(0).isEmpty &&
              !_over)
            ElevatedButton(
              onPressed: () {
                if (_e.passSevens(0)) {
                  SoundService.I.play('click');
                  setState(() {});
                  _pumpAI();
                }
              },
              child: const Text('PASS'),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _bidPanel() {
    final c = _e.cfg;
    if (_e.phase != 'bid' ||
        _e.currentBidder != 0 ||
        _e.needTrumpPick ||
        _over) {
      return const SizedBox.shrink();
    }
    final high = _e.bids.fold(0, (a, b) => b > a ? b : a);
    if (c.bidStyle == 'takeIt') {
      return _panel(
        Wrap(
          spacing: 10,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Take the trump?',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            ElevatedButton(
              onPressed: () => _humanBid(1),
              child: const Text('TAKE IT'),
            ),
            OutlinedButton(
              onPressed: () => _humanBid(0),
              child: const Text('Pass'),
            ),
          ],
        ),
      );
    }
    final unit = c.bidUnit == 'points' ? 'pts' : 'tricks';
    return _panel(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('High bid: $high $unit - name your bid',
              style:
                  const TextStyle(color: Colors.white, fontSize: 13)),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, color: Colors.white),
                padding: const EdgeInsets.all(12),
                onPressed: _bidVal > c.bidMin
                    ? () => setState(() => _bidVal--)
                    : null,
              ),
              Text('$_bidVal',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white),
                padding: const EdgeInsets.all(12),
                onPressed: _bidVal < c.bidMax
                    ? () => setState(() => _bidVal++)
                    : null,
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _humanBid(_bidVal),
                child: const Text('BID'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _trumpPicker() {
    if (!_e.needTrumpPick || _over) return const SizedBox.shrink();
    return _panel(
      Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Trump:',
              style: TextStyle(color: Colors.white, fontSize: 14)),
          for (int s = 0; s < 4; s++)
            GestureDetector(
              onTap: () => _humanTrump(s),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: QCardColors.gold, width: 2),
                ),
                child: Text(
                  const [
                    '\u2660',
                    '\u2665',
                    '\u2666',
                    '\u2663'
                  ][s],
                  style: TextStyle(
                    fontSize: 26,
                    color: (s == 1 || s == 2)
                        ? const Color(0xFFC0392B)
                        : const Color(0xFF1F2A37),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _handArea(double cw) {
    final hand = _e.hands[0];
    Set<TCard>? legal;
    if (!_over && _e.phase == 'play' && _e.turn == 0) {
      if (_e.cfg.uiMode == 'trick') {
        legal = _e.legalPlays(0).toSet();
      } else if (_e.cfg.uiMode == 'sevens') {
        legal = _e.sevensLegal(0).toSet();
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 6),
            for (final c in hand)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _card(
                  c,
                  cw,
                  dimmed: legal != null && !legal.contains(c),
                  selected: c == _hintGlow || c == _selCard,
                  onTap: () => _tapHandCard(c),
                ),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _controlsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            iconSize: 26,
            padding: const EdgeInsets.all(11),
            onPressed: () => Navigator.maybePop(context),
          ),
          IconButton(
            tooltip: 'Hint',
            icon: const Icon(Icons.lightbulb, color: Colors.white),
            iconSize: 26,
            padding: const EdgeInsets.all(11),
            onPressed: _doHint,
          ),
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo, color: Colors.white),
            iconSize: 26,
            padding: const EdgeInsets.all(11),
            onPressed: _e.canUndo ? _doUndo : null,
          ),
          IconButton(
            tooltip: 'New match',
            icon: const Icon(Icons.refresh, color: Colors.white),
            iconSize: 26,
            padding: const EdgeInsets.all(11),
            onPressed: _restart,
          ),
          IconButton(
            tooltip: _paused ? 'Resume' : 'Pause',
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause,
                color: Colors.white),
            iconSize: 26,
            padding: const EdgeInsets.all(11),
            onPressed: () {
              SoundService.I.play('click');
              setState(() => _paused = !_paused);
              if (!_paused) _pumpAI();
            },
          ),
        ],
      ),
    );
  }

  Widget _messageBar() {
    final msg = _message.isNotEmpty ? _message : _e.statusLine;
    if (msg.isEmpty) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(msg,
          textAlign: TextAlign.center,
          style:
              const TextStyle(color: Colors.white, fontSize: 13)),
    );
  }

  Widget _buildPauseOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: ElevatedButton(
            onPressed: () => setState(() => _paused = false),
            child: const Text('RESUME'),
          ),
        ),
      ),
    );
  }

  Widget _buildEndOverlay() {
    final c = _e.cfg;
    final detail = c.teamPlay
        ? 'Your team ${_e.teamScore(0)} - Rivals ${_e.teamScore(1)}'
        : 'Your score: ${_e.matchScore[0]}';
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.65),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: QCardColors.bgMid,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: QCardColors.gold, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    _won
                        ? Icons.emoji_events
                        : Icons.sentiment_dissatisfied,
                    size: 52,
                    color: QCardColors.gold),
                const SizedBox(height: 10),
                Text(_won ? 'You Win!' : 'Match Over',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Call the trump. Deliver the tricks.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text(detail,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                        onPressed: _restart,
                        child: const Text('PLAY AGAIN')),
                    OutlinedButton(
                        onPressed: () => Navigator.maybePop(context),
                        child: const Text('MODES')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================ UI ============================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QCardColors.bgDark,
      body: QFeltScaffold(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, cs) {
            final landscape = cs.maxWidth > cs.maxHeight;
            return landscape
                ? _buildLandscape(cs)
                : _buildPortrait(cs);
          }),
        ),
        overlays: [
          if (_paused && !_over) _buildPauseOverlay(),
          if (_over) _buildEndOverlay(),
        ],
      ),
    );
  }

  Widget _buildPortrait(BoxConstraints cs) {
    final cw = (cs.maxWidth / 8.5).clamp(40.0, 64.0);
    return Column(
      children: [
        _scoreBar(),
        const SizedBox(height: 2),
        _statusRow(),
        _kidsBanner(),
        Expanded(child: _tableArea(cw)),
        _trumpPicker(),
        _bidPanel(),
        _handArea(cw),
        _controlsRow(),
        _messageBar(),
      ],
    );
  }

  Widget _buildLandscape(BoxConstraints cs) {
    final cw = (cs.maxHeight / 8.5).clamp(36.0, 58.0);
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _scoreBar(),
              _statusRow(),
              Expanded(child: _tableArea(cw)),
              _handArea(cw),
            ],
          ),
        ),
        SizedBox(
          width: 200,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _kidsBanner(),
                _trumpPicker(),
                _bidPanel(),
                _controlsRow(),
                _messageBar(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
