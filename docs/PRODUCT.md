# Upside: product direction

Upside is built to compete with the best budgeting apps (Monarch, YNAB,
Copilot, Rocket Money). Today two people use it: Ron and Jadira. Their
accounts, banks and way of budgeting are the test bed, not the spec.

## Rules for every change

- **Nothing specific to one household in code.** No names, banks, payees or
  amounts baked in. Behavior comes from what the user sets or teaches
  (sorting a purchase, answering a question), never from what we know about Ron.
- **Guess, then ask once.** When Upside isn't sure (is "Ronald Tejada" one of
  you? what is a Zelle to someone new for?), it asks a single clear question
  and remembers the answer. No silent guesses that change money totals.
- **One set of numbers.** Every screen counts spending money, limits and
  overspending the same way.
- **Everything learned is visible and editable** (People you pay, Categories).
- **Screens say what's true and what to do; How Upside works says why.**
  At most one short line of explanation on a screen, only when it changes a
  decision or says what a tap will do. Everything else goes in the page,
  reached with Learn more.
- **Apple quality.** Plain words, few of them; calm by default; clear next
  step; haptics and system patterns.

## What makes it different

- Built for couples and households sharing one budget.
- A plan that saves first: savings, then cards, then trips and goals, then limits.
- Overspending is called out and paid for on purpose, never hidden.
- Zelle and Venmo sorted by person, the way people actually use them.

## Before others can use it

1. First-run setup that works without help.
2. Households of 1 to 4 people (today: exactly 2).
3. Bank wording beyond the banks we use (pair-matching already works anywhere).
4. Later, for selling: a new name (Upside is taken), a privacy policy, and a
   bank connection users don't set up themselves (needs a server).

## One vocabulary

The same thing has one name everywhere: on every screen, in How Upside works, in release notes.

| Say | Means | Not |
|---|---|---|
| **to spend** (label), **spending money** (in a sentence) | What's left of income after bills, savings, cards, trips and goals | "safe to spend", "available", "budget" |
| **left to spend** | To spend, minus what's been spent | "remaining", "safe to spend" |
| **limit** | What one everyday category has this month | "budget" for a category |
| **not in a limit** | Spending money no limit has claimed | "not in any limit", "unassigned", "spare" |
| **set aside** | Money taken off the top for trips and goals | "reserved", "saved for" |
| **over**, **overspending** | Spent past a limit (or past its usual, with no limit) | "overrun", "deficit" |
| **held** | A bill expected but not paid yet, still counted | "reserved", "pending" |
| **choose what gives** | Paying for being over, by less savings, cards, trips, goals or limits with room left | "rebalance", "fix" |

## Touch

Every action is a tap or a swipe. No long-press menus: nothing on screen says
they're there. A row that looks tappable opens; a row you'd swipe has swipe
actions (left: the main action, e.g. Stop, Business; right: the positive one,
e.g. Paid). Anything that changes money shows Undo.
