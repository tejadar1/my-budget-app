# Upside: how the money works

The rules every screen follows, and the test that holds each one. If a rule
here and the app ever disagree, the app is wrong. Amounts are cents.

## The month

| Rule | Checked by |
|---|---|
| **To spend** = income + money carried in − bills + bills paid from a goal − savings − card paydown − trips − goals + rolled-over limits | `testMonthPlanIsIncomeMinusBillsSavingsTripsThenSpending`, `BudgetInvariantTests.check` |
| **Left to spend** = to spend − everyday spent | `check` (every household, every step) |
| **Spent** is the sum of each category's spending; a refund nets out inside its own category | `testARefundWithNothingBoughtYetDoesntMakeCategoriesDisagreeWithTheTotal`, `check` |
| Transfers, business purchases and paychecks are never spending; transfers and business are never income | `check`, random action "a transfer or business purchase" |
| A new purchase moves spent, everyday spent and left to spend by exactly its amount | `testAPurchaseAddsExactlyItsAmountEverywhere` |
| Income to plan on: the amount you typed, else your usual; extra income counts only once it has a job | `testBudgetAndPlanCountIncomeTheSameWay`, `testPlannedIncomeAndWhenMoreComesIn` |
| Usual income is a typical paycheck (lower quarter), per source; a source quiet for 5 weeks (3 for weekly) stops counting, unless it paid this month or you said it's still paying | `testUsualPayIgnoresOvertimeAndTheSocialSecurityBump`, `testIncomePotAddsEachPersonAndDropsStoppedPay` |
| A finished month keeps its savings, card paydown, goals and trips as planned then | `testThePastDoesntChangeWhenSettingsDo`, `testLastMonthKeepsTheSavingsCardsAndGoalsItHad` |

## Bills

| Rule | Checked by |
|---|---|
| A bill is a payee charged about monthly; in a Bills category whatever the amount, elsewhere at a steady price | `testFindsBillsPriceIncreasesAndNewSubscriptions`, `testUtilitiesThatVaryAreDoneOnceTheUsualBillsArePaid` |
| A bills category holds: known bills at what's paid (or their latest amount while due), plus the part of its usual those bills don't explain | `testUtilitiesThatVaryAreDoneOnceTheUsualBillsArePaid`, `testBillsCountAtLeastTheirUsualAmount` |
| Paid under another name (same company, or its category for about its amount) counts as paid; a look-alike in another category doesn't | `testABillPaidUnderAnotherNameCountsAsPaid`, `testABillPaidThroughBillPay…`, `testAShirtIsntAWaterBill` |
| Paid, Paid for the month and Stop free the money; Restart and Undo put it back exactly | `testABillYouSayIsPaidStopsBeingDue`, `testStoppingABillFreesItsMoneyRightAway`, `testEveryOneTapChangeUndoesExactly` |
| Expected is never less than paid; bills paid add up | `check` |

## Limits and overspending

| Rule | Checked by |
|---|---|
| What limits use = each limit (a $0 limit is $0), or what's spent where that's more; Budget, Plan and Over the plan agree | `check`, `testALimitLoweredToZeroCountsAsZeroEverywhere` |
| Plan starts from Budget's exact to spend and adds only what you change | (by construction in `PlanView.numbers`) |
| What has to give = what limits use − to spend, to the nearest dollar | `check`, `testWhatHasToGiveIsRoundedLikeTheOverrunItself` |
| Choices: goals, trips, cards, savings; never more than each has; last choice first; nothing is taken on its own | `check`, `testOverspendingSaysWhatHasToGiveBottomOfThePlanFirst`, `testTheLastChoiceComesFirstNextTime` |
| A choice always helps, the category stays over, and Undo restores everything | random actions "choose" and "choose, then undo" |
| Adjust limit fits as it says, including at $0 | random action "adjust", `testAZeroLimitIsZeroWhetherForThisMonthOrFromNowOn` |
| Needs attention matches Over the plan, category by category | `check` |

## Bank sync and two phones

| Rule | Checked by |
|---|---|
| The same bank data twice changes nothing; a pending charge goes once its final charge arrives | `testABankSyncAppliedTwiceChangesNothing`, `testAPendingChargeGoesOnceItsFinalChargeArrivesHoweverOld` |
| A paycheck is never a transfer; your own "not spending" choice stays | `testAPaycheckIsNeverATransfer…`, `testADepositYouMarkedNotSpendingStaysThatWay` |
| The transfer check settles (twice = once) and never touches income | random action "sync" |
| Two phones merge field by field: each phone's change survives the other's refresh | `testOnePhonesRefreshDoesntWipeTheOthersBusinessOrIncome`, random action "the other phone" |

## End to end (the app on sample data)

Stop a bill and restart it; stop one and Undo from the toast; choose what
gives and undo; open Income from Budget; take an income source out and put
it back; open Trips; Start the month; Saving & trips; Adjust limit from a
category; answer a subscription question; How Upside works from Settings and
from Learn more. (`UpsideUITests`)
