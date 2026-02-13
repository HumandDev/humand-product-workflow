# Feature Refinement: Activity Score Formula (Web + Mobile)

## Requested Change

Define activity score as:

```text
activityScore = (posts * 20) + (comments * 10) + (reactions * 2)
```

Target surfaces: web and mobile.

---

## Validated Current State (evidence-backed)

### Backend (humand-main-api)

- Group activity score currently uses **posts=5, comments=1, reactions=0**:
  - `humand-packages/monolith/src/api/modules/groups/infrastructure/adapters/groupStatsAdapter.ts`
  - Current expression: `SUM(post * 5) + SUM(comment * 1)`
- Reactions are explicitly excluded from group stats queries:
  - Query filters `resource_type` to `['post', 'comment']` in `groupStatsAdapter.ts`
- Active-members and summary windows are currently fixed to **last 28 days**:
  - `humand-packages/monolith/src/api/modules/groups/business/services/groupStatsService.ts`
  - `GROUP_STATS_LAST_28_DAYS = 28` in `.../groups/business/constants.ts`
- Existing tests assert old behavior (5/1 scoring, reactions ignored):
  - `humand-packages/monolith/test-integration/api/groups/groupStats.test.ts`

### Web (humand-web)

- Web consumes group stats endpoints:
  - `src/services/groups.ts`
  - `GET groups/:id/stats/summary`
  - `GET groups/:id/stats/most-active-members`
- Web renders activity score in Featured Members UI:
  - `src/pages/dashboard/groups/ManageGroup/components/FeaturedMembers.tsx`
- Web model includes:
  - `activityScore`, `postsCount`, `commentsCount`
  - `src/types/groups.ts`

### Mobile (humand-mobile)

- Mobile group services currently do **not** call `groups/:id/stats/most-active-members` or `groups/:id/stats/summary` (group-level member activity endpoints absent in `app/modules/group/services.ts`).
- Mobile group admin screens (e.g. `ConfigPanel/AdminPanel`) do not include a "featured members / activity score" entry point.

### Translations (hu-translations)

- Existing group copy describes weighted posts/comments but not reactions:
  - `locale/en/group.json` keys:
    - `activity_score_tooltip`
    - `activity_tooltip`
    - `featured_members_tooltip`

---

## Refined Functional Scope

## 1) Scoring Rule

- Replace group activity formula with:
  - `posts * 20 + comments * 10 + reactions * 2`
- Keep existing tie-break ordering for equal scores unless explicitly changed:
  - (currently sorted by activity score desc, then user id asc)

## 2) Data Source

- Continue using `group_post_events`.
- Include `resource_type = 'reaction'` in both:
  - summary aggregation
  - most-active-members aggregation

## 3) Time Window

- Maintain current 28-day behavior unless product requests configurability.

## 4) API Contract

- At minimum, keep backward-compatible fields:
  - `activityScore`, `postsCount`, `commentsCount`
- Recommended contract improvement:
  - add `reactionsCount` to most-active-members and summary DTOs for transparency/debuggability

---

## Web Scope

- No new screen required; existing Featured Members surface can consume new score immediately once backend changes are live.
- If `reactionsCount` is added:
  - optional UI: add reactions column or secondary metadata
  - update tooltips to explain 20/10/2 formula

Likely files:
- `src/pages/dashboard/groups/ManageGroup/components/FeaturedMembers.tsx`
- `src/types/groups.ts`
- `src/services/groups.ts` (only if DTO shape changes)

---

## Mobile Scope

Current gap: there is no visible mobile surface using group activity score.

Two implementation options:

1. **Minimal parity (backend-only impact):**
   - do not add UI in mobile now
   - mobile remains unaffected functionally

2. **True feature parity (recommended for request wording):**
   - add mobile group "Featured members" screen/section
   - add group stats service calls:
     - `GET /groups/:id/stats/summary`
     - `GET /groups/:id/stats/most-active-members`
   - wire navigation entry from group admin tools

Likely files:
- `app/modules/group/services.ts`
- `app/modules/group/interfaces.ts`
- `app/modules/group/screens/GroupDetail/components/GroupLayout/components/ConfigPanel/AdminPanel/index.tsx`
- new screen/components under `app/modules/group/screens/GroupDetail/screens/`

---

## Risks / Product Decisions Needed

1. **Mobile ambiguity (blocking for "web and mobile")**
   - No existing mobile surface for this metric was found.
   - Need decision: backend-only parity vs. new mobile UI.

2. **Score interpretability**
   - If reactions affect score but reactions are not displayed, users can see "unexpected" score jumps.
   - Recommendation: expose `reactionsCount` in API + UI/report.

3. **Ranking shifts**
   - Changing from `5/1/0` to `20/10/2` materially changes rank outcomes.
   - This should be explicitly accepted by product.

---

## Acceptance Criteria (proposed)

1. For a user with `P` posts, `C` comments, `R` reactions in 28-day window:
   - score equals `20P + 10C + 2R`.
2. Group summary endpoint returns score computed with same formula and window.
3. Most-active-members endpoint ranking uses updated score (desc), tie-broken deterministically.
4. Existing integration tests in `groupStats.test.ts` are updated to include reactions in score assertions.
5. Web displays updated score correctly on Featured Members.
6. Mobile scope resolved explicitly:
   - either "no UI change (backend parity only)" or "new mobile surface shipped".
7. Tooltips/copy reflect reactions contribution (translation updates in `hu-translations`).

---

## Suggested Execution Order

1. **Backend first** (`humand-main-api`)
2. **Web** (`humand-web`)
3. **Mobile** (`humand-mobile`, if UI parity confirmed)
4. **Translations** (`hu-translations`)

