# Upside release notes

Newest first. The top section goes into TestFlight's "What to Test" for each build.

## Next (0.34.7): Room from anywhere
- Adjust limit: when other categories don't have enough room, it now also offers to put less toward savings, cards, trips or goals, right there ("Pay $100 less on cards a month", "Save $100 less this month"). No trip back to Plan. "From now on" changes the monthly amount; "Just this month" changes only this month. Goals only give for this month.

## 0.34.6: Steady
- Fixed: Adjust limit on a category's screen closed by itself the first time you opened it.
- Built on Apple's newer Mac build machines with the iOS 26.5 SDK; builds will move to the iOS 27 SDK on their own once it's available there.

## 0.34.5: Smoother
- Sort categories: the ↑↓ button next to Categories on Budget sorts by Closest to the limit (the usual order), Most left, Most spent, or Name. Remembered on this phone.
- Category names are never cut short: the amount sits under the name.
- Long-press a category on Budget: Adjust limit, See purchases, or Trends.
- Fix a purchase in place: in a category's purchases, swipe left for Move or Business, or long-press to move it straight to another category. Handy for the odd charge that landed in the wrong place and inflates your usual.
- Pull down on Budget to sync your banks, as on Accounts.
- Plan tucks away categories you never use (no limit, no usual, nothing spent) behind "Show unused".
- Budget's card adds how fast you've been spending: "So far you've spent about $40 a day, faster than that."
- Trends: the bars use the whole chart now; your income moved into words ("That's about 31% of what comes in").
- Light haptic taps when you save Plan, adjust a limit, choose what gives, hide a warning, sort, or move a purchase.

## 0.34.4: No more loop
- Fixed: Plan offered "Save the $X not in any limit" with money that was already covering a category that went over. Saving it left that category uncovered on Budget, which sent you back to Plan. Plan now counts spending past a limit the same way Budget does, so it only offers money nothing is using.
- Fixed the same mix-up on Budget's Details: "Not in any limit · put it toward savings" no longer offers money that's covering overspending.
- Fixed: Plan counted extra income (a bonus, a third paycheck) as spending money before you gave it a job; Budget didn't. Both now wait until you choose what it's for.
- Fixed: Credit cards said you were behind on paydown after you chose "Pay less on cards" this month. It now uses this month's amount.
- Fixed: last month's wrap-up was worked out with today's savings and card amounts and left out goals. Each month now keeps the savings, card paydown and goals it had.
- Lowering limits to pay for overspending no longer sets off "80% of your limit" alerts for those categories; only going past them does.
- Trips: a month you chose to put less toward trips isn't counted as overspent.
- Plan's limits note says how much spending past limits uses ("Spending past limits uses another $33").

## 0.34.3: Adjust a limit where you see it
- Tap a category, then Adjust limit, to change just that one. Pick From now on or Just this month.
- It checks right away whether it fits what you have. If raising it goes past that, it says by how much and offers to take it from categories with room left ("Take $100 from Shopping · $267 left"). Save waits until it fits. Lowering a limit is always fine.
- The category screen also shows the limit next to what's spent.
- Fixed: Plan said "Nothing is over its limit" when a category was over but money not in any limit covered it. It now says so.

## 0.34.2: Nothing left to do
- Plan no longer asks you to "Choose what gives" for overspending you've already paid for. It says "2 categories are over, and it's paid for: … Nothing else to do."
- "A big cut · Step down to it instead" shows only while planning the month, not on limits you lowered for this month only.

## 0.34.1: Clear about what to do
- When limits add up to more than you have, Plan says so once, in one sentence, with one button: "Choose what gives". Before, it only said it in red at the bottom, with nothing to press.
- Choose what gives now starts with lowering limits that still have room this month ("Shopping $300 → $200"), then the bottom of your plan: goals, trips, cards, savings. What went over stays over; your standing limits don't change.
- The same goes for Needs attention: "Limits are $2,769 more than you have" opens those choices instead of Plan.
- Quieter limit rows: what's spent and your usual in gray, and at most one short note ("November only", "Changed from $50") in gray instead of green. Suggested amounts show only while you're planning the month, where a button uses them.
- Overspending you've paid for leaves Needs attention: once you choose what gives, the row goes. The category still shows over in Categories, and the recap names it. What's left of the gap, if anything, shows as "Limits are $X more than you have".
- Hide a warning: over, on pace, or limits past what you have. Tap the ✕ (or long-press, Hide until it changes). It stays hidden this month unless the amount grows.
- Fixed: a small limit stepping down (Gifts $30 → $20) said "about 60 months" and never moved. Each step is now at least $10.

## 0.34: Overspending, called out
- Going over a limit is called out instead of covered. Needs attention says "Dining & Bars is $100 over" and what it costs: "Comes out of cards or savings unless you spend less elsewhere". The category stays over all month; its limit isn't raised to hide it.
- Tap it to see what drove it (purchases, the biggest one) and choose what gives, starting from the bottom of your plan: put less toward goals, trips, pay less on cards, or save less, for this month only. Savings comes last and is never chosen for you. Or spend less elsewhere: it shows which categories have room, and nothing changes.
- Money not in any limit pays first, and it says so: "$100 less left at month end".
- On pace: "Dining is on pace to go $80 over" after the first week, before it happens.
- Plan shows what this month gave up ("This month you paid $100 less on cards"). "Cover overspending" is gone.
- The month's recap names it: "To pay for it, you saved $100 less than planned."
- Business purchases are never overspending: you'll be paid back, so nothing has to give. Business charges carried on a card no longer count toward card paydown.

## 0.33: Trends and year in review
- Trends, under More: what you spent each month for the last year (with your income as a line), one sentence on how it's going ("About $4,300 a month lately, $210 less than the three months before"), what changed last month compared with usual, and every category's last six months side by side. Tap any category for its purchases.
- Year in review, under More ("2026 so far"; in January, last year "in review"): money in and out for the year, where it went with each category's share, your highest and lowest months, how many months stayed within the plan, who spent what, the biggest purchases, and fees for the year. If your bank history starts mid-year, it says so.
- Trips stay out of the month-to-month comparisons, so a vacation doesn't look like a trend; the year counts them separately.
- Recap: when the month came in under the plan overall, it no longer says the month went past the plan; it says which category went past its own ("One category went past its plan: Entertainment (+$74).").

## 0.32.3: Plan the way you budget
- Plan works the way you budget: you set the limits; during the month you only cover overspending.
- While planning the month (from the wrap-up, the first days of the month, or before anything's spent): "Start from what you usually spend" fills the limits, fit to what you have.
- Once the month is underway, the one button is "Cover overspending", shown only when a category is over. It raises each one for this month only, from money not in a limit and then from categories with room left, and lists exactly what moved. Nothing else changes: not your other limits, not savings, cards or trips. Pressing it again does nothing.
- If there isn't room to cover it all, it says how far the month is past the plan instead of trimming things you chose.
- The month's recap starts with where it went off plan, compared with the plan you started the month with: "October went $490 past the plan. Most of it: Dining & Bars (+$310) and Shopping (+$180)." Each line says what drove it: "Planned $500 · spent $810 · 14 purchases, biggest $95 at Nobu". Categories under plan are listed as "Went well".
- Gone: "Make limits fit" and "Rebalance the rest of the month", which recalculated every limit.

## 0.32.2: Better guesses
- Better guesses for stores Upside doesn't know (your Robinhood card sends no categories). It reads the name: "Frankies Dogs" → Dining, "Etix Ticket" → Entertainment, "Zeffy" → Gifts, plus words from stores you've already sorted. Old "Shopping?" guesses get another look.
- When there's truly nothing to go on, Check these asks "Choose a category" instead of guessing Shopping.

## 0.32.1: Clearer Plan buttons
- Plan has fewer, clearer buttons. At the top, only when something doesn't fit, one sentence and one button: "Make it fit" when the plan is more than your income, or "Put $X less toward trips" when you usually spend more than you have.
- Everyday limits has one big button that says what it will do: "Make limits fit" (trims limits, then trips and card paydown), "Rebalance the rest of November", or "Use recommended limits".
- You see where you ended up right under the button you pressed: "Fits: limits $3,950 of $3,992 to spend" (or how much is still short), what changed, and Undo.
- No button lowers savings anymore; only its own slider does.
- Money no limit uses: one "Save the $X not in any limit" button at the end of the limits.

## 0.32: Save first, plan realistically
- Extra income waits for a job. A bonus, overtime or a third paycheck no longer turns into spending money on its own. Needs attention says "$1,700 more came in than planned", and saving it is the first choice; you can also put it toward cards or add it to spending money.
- Payday reminder: when a paycheck lands and this month's savings aren't done, you get "Payday: move $750 to savings", that paycheck's share. Turn it off in Settings › Alerts.
- Savings is protected. Fix it for me trims trips and card paydown but no longer cuts savings; if that isn't enough, it says how much is still short.
- Plan vs. what you usually spend: when your usual everyday spending is more than you have to spend, Plan says by how much and offers to put less toward trips.
- Step down to a goal. A limit far under what you usually spend ("Usual $3,099: a big cut") can step down instead: it starts 10% under your usual and drops 10% each month you stay within it, until it reaches your goal. A month over repeats the step.
- Clearer labels in Plan: "This month only" for covers and money already spent; "changed from here on" for changes that carry into next month.
- Rebalance is a big green button.
- Last month's plan is kept when this month's starts, so last month's extra savings, covers and leftovers still add up in its recap and wrap-up.

## 0.31: Plan, adjust, look back
- Plan the month at the start: the month-end wrap-up now ends with "Plan November". That save is the month's plan. Without it, changes on the 1st–5th still count as planning.
- After that, changes are adjustments. Plan says so at the top, and "Use recommended limits" becomes "Rebalance the rest of November": it covers what's already spent and fits the rest to what's left.
- When two or more categories are over, Needs attention shows one row ("4 categories are $768 over") that opens Plan already rebalanced. Review it, then Save. One category over still offers Cover.
- Adjusted limits in Plan show what the plan had: "Planned $0 · adjusted for this month".
- The month's recap shows planned, adjusted and spent for each category over the plan, and lists spending the plan had no limit for, with a suggested limit.
- Recommended limits cover what's already spent: a category is never set below the money already gone this month, and only the room above that is trimmed. Plan shows "$490 spent so far → $490" for these.
- Those raises are for this month only. Next month the category goes back to its usual limit (or none).
- Month end judges against your original plan. The first time you change the plan after spending starts, the app keeps a copy of the plan as it stood; the monthly recap compares spending with that copy ("over plan"), so mid-month adjustments don't erase what went differently. Your changes still carry into next month.

## 0.30.1: Plan on a typical paycheck
- Usual income now plans on a typical paycheck from the last 6 months, leaning low, instead of the average. Overtime, bonuses and the higher fall paychecks after Social Security stops being withheld no longer raise the plan; when they come, they show up as money left over at month end.

## 0.30: A simpler Budget page
- Budget reads top to bottom: how much you can spend, what needs you, savings, categories, goals and trips, then More.
- Needs attention: one list, shown only when something needs you, with a row each for a bank that isn't syncing, a category over its limit, last month's wrap-up, purchases to check, and limits that don't fit. Each row opens a screen that explains it.
- Last month's wrap-up is now step by step, with the facts first: "You planned to save $1,500 and $502 went in. The other $998 should still be in checking." Then a clear choice: save it this month, or skip it. This replaces Catch up and Let it go.
- Cover opens its own screen: how much over, and which categories have room to cover it, for this month only (rounded up to the dollar).
- Categories are one list with a thin bar each, closest to its limit first, then Show all. The tiles and the By category totals are gone.
- Savings is one row with a bar; tap it for the details and What counted.
- Goals and trips share one section with a single Add button.
- More: Bills, Credit cards, Fees & fines, Business and the monthly recap in one Settings-style list.
- The Budget card no longer has an Adjust plan button; Plan is in the toolbar.
- Plan warns when savings, card paydown and trips don't fit in your income after bills: a red section with ways to lower them, and Save asks before keeping a plan that spends more than you make. The Budget card says so too.
- Plan's bar counts last month's money put to work this month (a catch-up or leftover), so it no longer shows a false "more than your income".

## 0.29.1: Month-end check-in
- A yearly or quarterly bill goal can name its bill category. The plan then stops holding back that bill's usual every month, and the month it's paid comes from the goal, not that month's money.
- Accounts a goal or the trip fund follows aren't counted as regular savings, so the same dollars don't count twice.
- Card paydown uses the balance you carry (what's owed minus this month's new charges) for "clear in about N months".
- The check-in also tells you when last month's everyday spending went over the plan.
- Month-end check-in: early each month, Budget shows what last month's plan said versus what happened. Savings not moved or card paydown not paid can be caught up this month (without cutting this month's spending money) or let go; unspent money gets Savings, Cards or Keep.
- Card paydown on the Budget card shows progress ("$344 of $1,301 paid down") and, in the last 10 days, how much is left to pay.
- Trip fund can be kept in a real savings account (Trip fund → Kept in). Its balance becomes the fund, and that money doesn't count as regular savings.
- Savings: buying or selling stock inside Robinhood (or any brokerage) no longer counts against what you saved; only money taken out of the account does.

## 0.29: Savings you can check
- Savings card: "What counted" lists the transfers behind "saved so far", so you can see where a number like $2 came from.
- Money arriving in a savings or investment account counts toward savings even when Upside can't match it to the transfer out (brokerage deposits often don't match). Interest, dividends and sales don't count.
- Saved & invested: open a transfer (or long-press it in Transactions) and turn on Saved & invested for money moved to investing, like Robinhood. It counts toward your savings, and future transfers worded the same way follow.

## 0.28, November 8 (sharing fixes)
- Share budget opens Apple's sharing screen reliably (it could fail silently with Face ID lock on), shows a spinner while it prepares, and explains any problem.
- Large-purchase alerts and bill detection look at whole purchases, so a split purchase isn't counted twice.
- With trips turned off, purchases no longer show a Trip picker.
- Leaving a shared budget, or the owner stopping sharing, keeps that phone's copy as its own budget (and says so) instead of bringing back old data.
- Settings: removed the old "Share with your partner · Coming soon" row; sharing lives in Settings → iCloud.

## 0.28, November 8 (iCloud, goals, splits)
- Sharing is private to the person you invite. Settings → iCloud lists who has access (joined or invited), Upside notifies you when someone joins, and warns if more than one person has access.
- Goals you track by hand fill up each month by what the plan set aside for them.
- Split a purchase: open it and tap "Split this purchase…" to divide it by category (groceries and home) or between the two of you (Half each). Each part counts in its own category and for its own person.
- Goals: add an emergency fund (with months of essentials covered), a yearly or quarterly bill (set aside monthly until it's due), or a big purchase. Each takes its monthly amount off the top in your plan. Long-press a goal to add to it, mark a bill paid, or delete it.
- Trips can be turned off: Settings → Plan for trips.
- Rollover: turn on "Roll over what's left" for a category (Settings → Categories) and unspent money adds to next month's limit.
- Early each month, Budget asks what to do with last month's unspent money: Savings, Cards or Keep.
- New alerts: bills due in two days (9am), checking running low (under your amount or under bills still due), and purchases over your amount. Each can be turned off in Settings.
- iCloud: your whole budget backs up to your private iCloud automatically and comes back on a new phone or after reinstalling.
- Share your budget: Settings → iCloud → Share budget sends an iCloud invite. Once accepted, both phones read and edit the same budget; changes from both are combined, not overwritten.
- Only your phone talks to the banks; the shared budget carries the results. The SimpleFIN key never goes to iCloud.
- Settings shows iCloud status ("Backed up 2 min ago") or what's wrong, with the reason.

## 0.28, November 7 (Plan and covers, fines)
- Tickets and fines go in Minimize with fees (aim for $0); a Tickets category you made moves there once. Any category's detail in Settings → Categories now has a Group picker: Everyday, Bills or Minimize. The tile is now "Fees & fines".
- Plan shows this month's limits including anything you covered, marked "Adjusted for this month". Saving the plan keeps those covers; a limit you change in Plan becomes your usual limit.

## 0.28, November 5 (SimpleFIN in the app)
- Cards: "Balance up since…" can no longer be more than what's owed, and needs a few months of card history first.
- Recap hides "Usual income" when it matches income. Trips say "On the trip" instead of "During and after".
- The bank warning only watches everyday accounts; mortgages and investments update less often.
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
