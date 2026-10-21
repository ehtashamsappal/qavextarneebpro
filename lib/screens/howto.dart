import 'package:flutter/material.dart';
import 'package:qavextarneebpro/core/app_state.dart';
import 'package:qavextarneebpro/widgets/ui.dart';

class HowToScreen extends StatelessWidget {
  const HowToScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBuilder(
      builder: (context, s) => QxScaffold(
        title: 'How to Play',
        body: ListView(
          children: const [
            QxCard(
              child: Text('HOW TO PLAY\n\nGoal: with your partner, be the first team to 41 points.\n\n- Partners sit across from each other. 13 cards each.\n- Bid 7 to 13 tricks. The highest bidder names the trump suit.\n- You must follow the led suit if you can. Highest trump wins, otherwise highest led card.\n- Only the bidding team can score: make the bid to score +bid, fail to lose -bid.\n- The defenders score nothing; their job is to break your bid.\n- First team to 41 wins the match.\n\nMODES\n- Classic: the pure race to 41.\n- Timed Run: 10 minutes; highest score when the clock stops wins.\n- Daily Challenge: one seeded deal per day; streaks earn bonus chips.\n- Zen Table: no timer, free hints and undo.\n- Kids Mode: gentle guidance, easy rivals.\n- Practice: free play with auto-hints.\n- AI Ladder: climb 8 rungs from Easy to Expert.\n- Tournament: 5 rounds, highest total takes the crown.\n\nSimplifications for mobile: no 13-bid sweep bonus; defenders never score,\nthey only try to break the contract.',
                  style: TextStyle(fontSize: 15, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
