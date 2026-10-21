import 'package:flutter_test/flutter_test.dart';
import 'package:qavextarneebpro/game/logic.dart';

final _cfg = gameConfig();

TrickEngine _fresh({int seed = 7}) {
  final e = TrickEngine(_cfg, aiLevel: 1);
  e.newMatch();
  e.newRound(seed: seed);
  return e;
}

/// Complete any bidding phase deterministically.
void _finishBidding(TrickEngine e) {
  int guard = 0;
  while (e.phase == 'bid' && !e.isMatchOver && guard++ < 20) {
    if (e.needTrumpPick) {
      e.setTrump(0);
      continue;
    }
    final s = e.currentBidder;
    if (s < 0) break;
    if (e.cfg.bidStyle == 'takeIt') {
      e.placeBid(s, s == e.cfg.players - 1 ? 1 : 0);
    } else {
      e.placeBid(s, e.cfg.bidMin);
    }
  }
}

void main() {
  test('config is sane', () {
    expect(_cfg.players, inInclusiveRange(2, 4));
    expect(_cfg.handSize, greaterThan(0));
    expect(_cfg.uiMode, isIn(['trick', 'capture', 'sevens']));
    expect(_cfg.scoreMode, isNotEmpty);
    expect(_cfg.gameId, isNotEmpty);
  });

  test('deal: every hand has handSize cards and play begins', () {
    final e = _fresh();
    _finishBidding(e);
    for (final h in e.hands) {
      expect(h.length, _cfg.handSize);
    }
    expect(e.phase, 'play');
  });

  test('bidding produces a winner and moves to play', () {
    final e = _fresh();
    _finishBidding(e);
    if (_cfg.bidding) {
      expect(e.bidWinner, inInclusiveRange(0, _cfg.players - 1));
      if (_cfg.trumpMode == 'bid') {
        expect(e.trump, inInclusiveRange(0, 3));
      }
    }
    expect(e.phase, 'play');
  });

  test('newMatch resets the score', () {
    final e = _fresh();
    _finishBidding(e);
    e.matchScore[0] = 99;
    e.newMatch();
    expect(e.matchScore, everyElement(0));
    expect(e.roundNo, 1);
  });

  group('trick play', () {
    test('must follow suit', () {
      final e = _fresh();
      _finishBidding(e);
      e.trump = 1;
      e.trick.clear();
      e.hands[0] = [const TCard(0, 5), const TCard(1, 7)];
      e.hands[1] = [const TCard(0, 9)];
      e.turn = 1;
      e.leader = 1;
      expect(e.playCard(1, const TCard(0, 9)), isTrue);
      final legal = e.legalPlays(0);
      expect(legal, [const TCard(0, 5)]);
      expect(e.playCard(0, const TCard(1, 7)), isFalse);
    });

    test('trump beats the led suit', () {
      final e = _fresh();
      e.trump = 1;
      e.trick.add(const TrickPlay(0, TCard(0, 14)));
      e.trick.add(const TrickPlay(1, TCard(1, 2)));
      expect(e.trickWinnerSeat(), 1);
    });

    test('highest led card wins without trump', () {
      final e = _fresh();
      e.trump = -1;
      e.trick.add(const TrickPlay(0, TCard(2, 10)));
      e.trick.add(const TrickPlay(1, TCard(2, 13)));
      expect(e.trickWinnerSeat(), 1);
    });

    test('undo restores the played card', () {
      final e = _fresh();
      _finishBidding(e);
      e.turn = 0;
      e.leader = 0;
      e.trick.clear();
      final before = e.hands[0].length;
      final card = e.legalPlays(0)[0];
      expect(e.playCard(0, card), isTrue);
      expect(e.hands[0].length, before - 1);
      expect(e.canUndo, isTrue);
      e.undo();
      expect(e.hands[0].length, before);
      expect(e.trick, isEmpty);
    });

    test('ai turn completes', () {
      final e = _fresh();
      _finishBidding(e);
      e.turn = 1;
      e.leader = 1;
      e.trick.clear();
      final before = e.hands[1].length;
      e.aiPlay(1);
      expect(e.hands[1].length, before - 1);
    });

    test('hint suggests a playable card', () {
      final e = _fresh();
      _finishBidding(e);
      e.turn = 0;
      e.trick.clear();
      final h = e.hintCard();
      expect(h, isNotNull);
      expect(e.hands[0], contains(h));
      expect(e.hintText(), isNotEmpty);
    });

    test('bowers: jack of trump is highest', () {
      final e = _fresh();
      e.trump = 0;
      e.trick.add(const TrickPlay(0, TCard(0, 14)));
      e.trick.add(const TrickPlay(1, TCard(0, 11)));
      expect(e.trickWinnerSeat(), 1);
      final e2 = _fresh();
      e2.trump = 0;
      e2.trick.add(const TrickPlay(0, TCard(0, 14)));
      e2.trick.add(const TrickPlay(1, TCard(3, 11)));
      expect(e2.trickWinnerSeat(), 1);
    }, skip: _cfg.bowers ? false : 'no bowers in this game');

    test('a full round completes without hanging', () {
      final e = TrickEngine(_cfg, aiLevel: 1);
      e.newMatch();
      final r0 = e.roundNo;
      _finishBidding(e);
      int inner = 0;
      while (e.phase == 'play' && e.roundNo == r0 && inner++ < 900) {
        e.aiPlay(e.turn);
      }
      expect(inner, lessThan(900));
      if (!e.isMatchOver && e.roundNo == r0) e.endRound();
      expect(e.roundNo == r0 + 1 || e.isMatchOver, isTrue);
    });
  }, skip: _cfg.uiMode != 'trick');

  group('round scoring', () {
    test('applyRoundScore follows the configured scoreMode', () {
      final e = _fresh();
      _finishBidding(e);
      final before = List.of(e.matchScore);
      final n = e.cfg.players;
      for (int p = 0; p < n; p++) {
        e.tricksTaken[p] = p == 0 ? 5 : 2;
        e.trickPoints[p] = p == 0 ? 40 : 10;
        e.captured[p] = <TCard>[];
      }
      if (e.bidWinner < 0) e.bidWinner = 0;
      if (e.cfg.bidding && e.bidTricks <= 0) {
        e.bidTricks = e.cfg.bidMin;
      }
      switch (e.cfg.scoreMode) {
        case 'bid':
          e.applyRoundScore();
          for (int p = 0; p < n; p++) {
            expect(e.matchScore[p], before[p] + e.cfg.bidMin);
          }
          break;
        case 'courtpiece':
          e.applyRoundScore();
          expect(e.matchScore[0], before[0] + 1);
          expect(e.matchScore[2], before[2] + 1);
          break;
        case 'avoid':
          e.captured[1] = [const TCard(1, 5)];
          if (n > 2) e.captured[2] = [const TCard(1, 9)];
          e.applyRoundScore();
          expect(e.matchScore[1], before[1] + e.cfg.heartsPts);
          if (n > 2) {
            expect(e.matchScore[2], before[2] + e.cfg.heartsPts);
          }
          expect(e.matchScore[0], before[0]);
          break;
        case 'contract':
          e.applyRoundScore();
          for (int p = 0; p < n; p++) {
            expect(e.matchScore[p], before[p] + (p == 0 ? 5 : 2));
          }
          break;
        case 'spades':
          e.applyRoundScore();
          expect(e.matchScore[0], before[0] + 10 * e.cfg.bidMin + (5 - e.cfg.bidMin));
          expect(e.matchScore[1], before[1] + 10 * e.cfg.bidMin + (2 - e.cfg.bidMin));
          break;
        case 'euchre':
          e.applyRoundScore();
          // take-it bidding: last seat takes; team of seat 3 has 4 tricks -> +1
          expect(e.matchScore[3], before[3] + 1);
          expect(e.matchScore[1], before[1] + 1);
          break;
        case 'bridge':
          e.applyRoundScore();
          expect(e.matchScore[0], before[0] + 25 * 7);
          expect(e.matchScore[2], before[2] + 25 * 7);
          break;
        case 'tarneeb':
          e.applyRoundScore();
          expect(e.matchScore[0], before[0] + e.bidTricks);
          expect(e.matchScore[2], before[2] + e.bidTricks);
          break;
        case 'tricks':
          e.applyRoundScore();
          for (int p = 0; p < n; p++) {
            expect(e.matchScore[p], before[p] + (p == 0 ? 5 : 2));
          }
          break;
        case 'points':
          e.applyRoundScore();
          if (e.cfg.pointsRule == 'twentynine') {
            expect(e.matchScore[0], before[0] + 1);
            expect(e.matchScore[2], before[2] + 1);
          } else if (e.cfg.pointsRule == 'skat') {
            expect(e.matchScore[0], before[0] - 2 * e.bidTricks);
          } else if (e.cfg.pointsRule == 'pinochle') {
            final tt = 50 + e.meldPts[0] + e.meldPts[2];
            expect(e.matchScore[0], before[0] + tt);
            expect(e.matchScore[2], before[2] + tt);
          } else if (e.cfg.pointsRule == 'briscola') {
            expect(e.matchScore[0], before[0] + 1);
          }
          break;
        case 'capture':
          if (e.cfg.captureRule == 'scopa') {
            e.captured[0] = [
              const TCard(2, 7),
              const TCard(2, 5),
              const TCard(0, 3),
              const TCard(1, 4),
              const TCard(3, 6),
            ];
            e.captured[1] = [
              const TCard(2, 2),
              const TCard(0, 9),
              const TCard(1, 10),
            ];
            e.scopaCount[0] = 1;
            e.applyRoundScore();
            // most cards + most coins + most sevens + settebello + 1 scopa
            expect(e.matchScore[0], before[0] + 5);
            expect(e.matchScore[1], before[1]);
          } else {
            e.captured[0] = [
              const TCard(0, 1),
              const TCard(2, 10),
              const TCard(3, 5),
            ];
            e.captured[1] = [
              const TCard(1, 11),
              const TCard(3, 2),
            ];
            e.pishtiCount[0] = 1;
            e.applyRoundScore();
            // p0: A=1 + 10D=3 + pishti 10 + most cards 3 = 17
            expect(e.matchScore[0], before[0] + 17);
            // p1: J=1 + 2C=2 = 3
            expect(e.matchScore[1], before[1] + 3);
          }
          break;
        case 'sevens':
          final lens = [for (final h in e.hands) h.length];
          e.applyRoundScore();
          for (int p = 0; p < n; p++) {
            expect(e.matchScore[p], before[p] + lens[p]);
          }
          break;
      }
    });
  });

  group('capture', () {
    test('scopa: exact-sum subset is captured', () {
      final e = _fresh();
      e.table = [const TCard(0, 3), const TCard(1, 4), const TCard(2, 9)];
      e.hands[0] = [const TCard(3, 7)];
      e.hands[1] = [const TCard(3, 5)];
      e.turn = 0;
      expect(e.captureOptions(const TCard(3, 7)), isNotEmpty);
      expect(e.playCapture(0, const TCard(3, 7)), 'captured');
      expect(e.table, isEmpty);
      expect(e.captured[0].length, 3);
    }, skip: _cfg.captureRule != 'scopa');

    test('scopa: no matching sum tables the card', () {
      final e = _fresh();
      e.table = [const TCard(2, 9)];
      e.hands[0] = [const TCard(3, 7)];
      e.hands[1] = [const TCard(3, 5)];
      e.turn = 0;
      expect(e.playCapture(0, const TCard(3, 7)), 'tabled');
      expect(e.table.length, 2);
    }, skip: _cfg.captureRule != 'scopa');

    test('pishti: rank match sweeps the pile', () {
      final e = _fresh();
      e.table = [const TCard(0, 5), const TCard(1, 9)];
      e.hands[0] = [const TCard(2, 9)];
      e.hands[1] = [const TCard(3, 5)];
      e.turn = 0;
      expect(e.playCapture(0, const TCard(2, 9)), 'captured');
      expect(e.table, isEmpty);
      expect(e.captured[0].length, 3);
    }, skip: _cfg.captureRule != 'pishti');

    test('a full capture round completes without hanging', () {
      final e = TrickEngine(_cfg, aiLevel: 1);
      e.newMatch();
      final r0 = e.roundNo;
      int inner = 0;
      while (e.phase == 'play' && e.roundNo == r0 && inner++ < 1200) {
        e.aiCapture(e.turn);
      }
      expect(inner, lessThan(1200));
      expect(e.roundNo == r0 + 1 || e.isMatchOver, isTrue);
    });
  }, skip: _cfg.uiMode != 'capture');

  group('sevens', () {
    test('a seven starts its suit', () {
      final e = _fresh();
      e.hands[0] = [const TCard(2, 7), const TCard(0, 5)];
      e.hands[1] = [const TCard(0, 6)];
      e.turn = 0;
      expect(e.playSevens(0, const TCard(2, 7)), isTrue);
      expect(e.sevStarted[2], isTrue);
    });

    test('only adjacent ranks are legal after the seven', () {
      final e = _fresh();
      e.hands[0] = [const TCard(2, 7), const TCard(2, 8), const TCard(2, 9)];
      e.turn = 0;
      expect(e.playSevens(0, const TCard(2, 7)), isTrue);
      expect(e.sevensLegal(0), [const TCard(2, 8)]);
    });

    test('a full sevens round completes without hanging', () {
      final e = TrickEngine(_cfg, aiLevel: 1);
      e.newMatch();
      final r0 = e.roundNo;
      int inner = 0;
      while (e.phase == 'play' && e.roundNo == r0 && inner++ < 600) {
        e.aiSevens(e.turn);
      }
      expect(inner, lessThan(600));
      expect(e.roundNo == r0 + 1 || e.isMatchOver, isTrue);
    });
  }, skip: _cfg.uiMode != 'sevens');
}
