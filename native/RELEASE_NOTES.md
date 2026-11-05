# Upside release notes

Newest first. The top section goes into TestFlight's "What to Test" for each build.

## Next build
- Manage banks without leaving Upside: Settings → Manage banks (and Fix in SimpleFIN on the bank warning) opens SimpleFIN Bridge inside the app. Add a bank, sign in again or tap Adjust; Upside syncs when you close it.

## 0.28, November 4 (cover overspending)
- Over this month: categories past their limit show on Budget with Cover. Pick another category with room (or money not in a limit) and it moves for this month only, so overspending doesn't quietly eat into savings.
- Savings card says "$X saved of $Y", what counts as saved, and how much is left to move this month.
- Accounts warns when a bank stops sending new activity (3+ days) or SimpleFIN reports a connection problem, with a link to SimpleFIN Bridge to fix it. Each account shows when the bank last updated it.
- Income: paychecks into a bank that only shared a few weeks of history now count. Upside estimates the usual month from the paychecks it can see (two checks two weeks apart = two a month) and marks them "estimated from recent pay".

## 0.28, November 4 (simpler Budget and Plan)
- Budget card leads with one number and bar; tap Details for income, bills, savings and trips.
- Savings is one number, set in Plan; the Savings card shows how much has moved toward it.
- Plan shows where your income goes as one bar, with sliders for savings, card paydown and trips, and what each means (a year of savings, months to clear cards).
- Plan: "Use my usual income" switch, and an "Extra just this month" amount (replaces the separate Save money screen).
- Limits change only in Plan; Categories in Settings shows how each was set.
- First run shows only the names card and setup steps; Fees and Trips appear once there's data.

## 0.28, November 4 (Apple polish)
- Store names read cleanly: "SQ *BLUE BOTTLE #12" shows as "Blue Bottle". The bank's text is still on the purchase screen.
- Purchases show a category icon, with a small dot for whose account it was.
- Spending shows without a minus sign; money in shows with a plus, like Apple Card.
- Big numbers grow with your iPhone's Text Size setting.
- Shorter explanations under each section.
- Same words everywhere: "left to pay" for bills, "Categories & limits" in Settings.
- Hide account is no longer red, since you can undo it. Month arrows are easier to tap.
- Business shows a clear empty screen when there's nothing yet.
- First run asks for your names, then shows the setup steps; the plan appears once there's data.
- New categories are suggested after 3 purchases, not 1.

## 0.28, November 3 (afternoon)
- Subscriptions: a store that bills several things is checked one price at a time, so iCloud and Apple One are both found, and Tesla Connectivity is found apart from charging (which stays in Gas & Auto).
- More subscription names recognized, like Apple Services and Tesla subscriptions.

## 0.28, November 3 (morning)
- Plan: when recommended limits still don't fit, it shows how much you're short and how to close it: pay less on cards, put less toward trips, save less, or cut limits deeper this month.
- Fix it for me: one button that closes the gap for you. It trims flexible limits a bit more, then takes from trips, then card paydown, and savings last, and says what it changed.

## 0.28, November 3 (late)
- Not a bill: the store's purchases move to an everyday category (check it in Check these), so the bills total drops and they count against your limits. They stay out of Bills after syncs.
- It's a bill: long-press any purchase in Transactions to file it under a bill category.
- Bills & subscriptions tucks the stores you removed into a collapsed "Not bills" list.
- Income to plan for is used as you enter it, even above your usual (your usual can be low when a bank only shares a few weeks). Plan says how far above usual you are.
- Plan lists each paycheck in the income pot, with whose it is (tap to change) and what it adds to a normal month. Pay that stops for 5 weeks stops counting toward your usual.

## 0.28, November 3 (evening)
- Plan counts a normal two-paycheck month as your usual income. A third paycheck shows up as a bonus when it lands.
- Planned income above your usual only counts once it arrives. Until then the plan uses your usual.
- Recommended limits cut at most 25% below usual in a month. If that isn't enough, the plan shows how far over you are.
- Bills: the big number is everything left to pay this month (it matches the plan), with what's paid so far beside it.
- Check these: each purchase shows its guessed category as a button. Tap Right to agree, or tap the category to change it.
- Groceries is now Groceries & Liquor, and liquor and wine shops (Total Wine, Astor Wines, Drizly…) go there. Wine bars stay in Dining & Bars.
- New standard categories: Home & Repairs (contractors, Home Depot, cleaning, furniture), Fitness (gyms, classes, Peloton), and Pets, split from Kids.
- Rent / Mortgage also catches co-op and condo common charges and HOA fees.
- Savings shows where its amount comes from: every month (set in Plan) and any extra just this month, which you can remove in Plan.
- Savings card figures are clearer: moved to savings so far, usually moved, extra paid on cards.
- Accounts: long-press a card to hide it. Accounts at $0 with no activity in 90 days move to an "Empty accounts" group at the bottom.

## 0.28, November 2 (cards in the plan, not a bill)

- Credit cards live in one place: the Card paydown line in the month plan. Tap it for what's owed, this month's payments against your target, and each card.
- Bills & subscriptions: swipe left on anything that isn't one ("Not a bill" / "Not a subscription"); hidden ones can be shown again.
- The Adjust plan button is shorter.
- Lowering limits frees money: Plan shows what's unassigned and adds it to savings or card paydown in one tap; the month card shows "Not in any limit".
- Categories without a limit count their usual spending, so "unassigned" money is real money.

## 0.28, November 2 (one Plan screen)

- One Plan screen (Budget > Plan, or Adjust plan on the month card): savings, card paydown and trips each month, then recommended everyday limits that fit what's left.
- Recommended limits update as you change savings, cards or trips; "Use recommended limits" applies them.
- Income to plan for: set the income you plan around. If more comes in, the extra counts; finished months use what really arrived.

Try: Budget > Plan, raise savings, and watch the recommended limits.

## 0.28, November 2 (business expenses)

- Mark a purchase as a business expense (purchase sheet, or long-press in Transactions). It stays out of your budget.
- Reimbursements (Expensify, Concur, Navan, "reimbursement") are recognized and don't count as income.
- Budget shows what you're still owed; tap it for business purchases and what's been paid back. Transactions has a Business filter.

## 0.28, November 2 (pay yourself first)

- Pay yourself first: set savings and card paydown each month (with a suggestion to clear your cards in 6 or 12 months). They come off the top with trips and bills.
- Everyday limits fit what's left: they start from your usual, then shopping, dining and other flexible spending is trimmed until everything fits.
- Recalculate in Limits now fits your plan instead of copying your averages.
- The credit card check lives on Budget only (next to card paydown); Accounts shows balances.

Try: Budget > Savings > Pay yourself first.

## 0.28, November 2 (subscriptions)

- Upside finds subscriptions on its own: the same price around the same day every month. Found ones show in Check these.
- About 60 more subscription services recognized by name.
- On a category page, tap a month in the chart (or the list under it) to see that month's purchases.

## 0.28, November 2 (savings and subtotals)

- Savings card right under the plan: this month's goal, what's actually been saved or invested, and whether spending leaves room for it.
- "By category" subtotals: everyday against its limits, bills against what's expected, fees, and trips.
- Category sections show what's been spent in each.

## 0.28, November 2 (bills)

- Bills in the plan count at least each bill category's usual amount, so bills not paid yet are planned for.
- Tap Bills to see each category: paid so far, usual, and what's still to come.

## 0.28, November 2 (month plan)

- Budget now reads top-down: Income, minus Bills, Savings and Trips, leaves To spend.
- One number to watch: left to spend, with about how much a day.
- If your everyday limits add up to more than you have, Upside says so and trims them to fit.
- Tap Bills for what's paid and due, Savings to set or change your goal.
- Per-person amounts under the plan count everyday spending only, matching Spent; bills stay out of Top categories.

## 0.28, November 2 (Transactions tab)

- New Transactions tab: every purchase by month, with search by store or amount.
- Filter to All, To check or Transfers, and by category or person.
- Long-press to change a category, swipe right to confirm a guess, swipe left to mark a transfer.

Try: the Transactions tab, then long-press any purchase.

## 0.28, November 2 (income card wording)

- Safe to spend says when it's counting your usual income; "Left so far" counts only what's arrived.
- Check these: the "Sort all" question stays on screen until you answer.

## 0.28, November 2 (trip fund)

- Trip fund: set aside an amount each month; anything tagged to a trip comes out of it, and what's unused carries over.
- The Income card shows what's set aside for trips, and Left over is after it.
- Each upcoming trip says whether the fund covers it, or how much a month would.
- Safe to spend: the Income card shows what you can still spend and keep your savings and trip money, after bills still due.
- The trip fund only gets what a month actually had left; overspending means less for trips.
- Each trip is paid for evenly from its first purchase through the month after it, and Safe to spend keeps that amount each month.

Try: Budget > Trips > Start a trip fund.

## 0.28, November 2 (sorting and cards)

- Many more restaurants recognized (chains and words like pizzeria, taqueria, pho, halal, steakhouse).
- Parking, garages, tolls, bridges and car repair go to Gas & Auto.
- Purchases Upside guessed earlier are re-checked against the new lists.
- Credit card check (charged vs paid, growing balances) is on the Budget page too.
- Re-sort moved to a "Start over" section at the bottom of Settings and asks twice.

## 0.28, November 2 (savings bars)

- Save money: each bar shows what you keep in gray and what you save in green.

## 0.28, November 2 (income)

- Income now comes first on the Budget page: this month's paychecks, your usual, and what's left after spending.
- A paycheck that usually lands on the 1st but arrives a day or two early counts for the month it's for.
- Weekly and every-two-weeks pay: months with an extra paycheck say so, and your usual income doesn't jump.
- Education (tuition, school, daycare) is a bill: it shows with your bills and the savings plan never trims it.

Try: the Income card at the top of Budget.

## 0.28, November 2 (morning)

- Every purchase is sorted automatically. "Check these" lists the few Upside guessed: tap ✓ or fix it once.
- Savings sits in the This month card. The plan shows the limit to stay under in each category; +$50, +$100 or "Most I can" trims more.
- Maximize and Minimize: saved & invested (savings, 529, Vanguard) next to fees & interest (card, plan and bank fees).
- New categories: Commuting & Rides (subway, LIRR, taxis, Uber), Car payment, Taxes. Rides moved out of Gas & Auto.
- Tap a limit to see the last 3 months behind it. "Recalculate" resets limits after you add a bank.
- Usual spending counts each bank only for the months it has history.
- Hide accounts you don't want in the budget.
- Over-limit bars keep each person's color, with the overspend in red.
- Settings switches are green.

Try: Check these on the Budget page, the savings line in This month, and Limits › tap a category.

## 0.28, November 1 (night)

- Golf shows up in Recommended categories.
- Dining & Bars is one category, with more bar names recognized.
- Uses the bank's merchant code (when sent) to sort unfamiliar stores.

## 0.28, November 1 (evening)

- Sorting one purchase offers to sort others with the same name.
- Usual income next to Income; the This month card always shows each person.
- Face ID lock covers open screens; Upside asks once for notification permission.
- All credit cards recognized; more card payments matched; recap can be swiped away.
- Lenny's-style regular spots no longer count as bills.
