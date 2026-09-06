# Vilvia Product & Release Roadmap

This is the authoritative roadmap for Vilvia. It defines the shortest responsible path from the current implementation to a real, secure, production-ready application for actual users in Sweden.

Agents must work through this roadmap in order. Any deviation must be justified by a newly discovered security, correctness, or release-blocking risk.

---

## Product Vision

Vilvia is a family and parenting platform for parents in Sweden, structured around four main product areas:

1.  **Resources**: Trusted knowledge hub for child development and parenting.
2.  **Events**: Discovery of family-relevant activities and meetups.
3.  **Community**: Safe parent-to-parent sharing and discussion.
4.  **Family & Child Rights**: Sensitive guidance on Swedish systems and rights.

---

## Phase 0: Baseline Verification (DONE)

- [x] **Authentication**: Supabase integration with local secure storage.
- [x] **Account Deletion**: Durable in-app flow and external HTTPS resource.
- [x] **Community MVP**: Posts, Comments, Reactions, and Reporting.
- [x] **Admin Moderation**: Triage queue for reports and content hiding.
- [x] **Events MVP**: Browsing upcoming events and Admin-only creation.
- [x] **Resources Sync**: Automated synchronization from MedlinePlus (English).
- [x] **Rate Limiting**: Basic in-memory backend rate limiting.

---

## Phase 1: Identity & Account Safety (P0)

*Goal: Ensure users can reliably register, access, and recover their accounts.*

- [ ] **Fix Registration & First-Login Profile Bootstrap**: Ensure profile data provided during Sign Up survives email verification and automatically loads on first login without repeated onboarding.
- [ ] **Password Reset Flow**: UI and deep-linking to handle Supabase recovery emails.
- [ ] **Auth & Session Hardening**: Protect Events and Community screens against auth-state race conditions; handle failed session restoration.

---

## Phase 2: Core Product Pillar Completion (P0/P1)

*Goal: Fill major gaps in the four product areas.*

### 1. Resources (Swedish Context)
- [ ] **Swedish Benefit Integration**: Add "Parental Rights & Benefits" category and source content (e.g. Försäkringskassan).
- [ ] **Provenance Metadata**: Explicitly store and display `last_reviewed_at` and `source_authority_type`.

### 2. Events (Attribution & Details)
- [ ] **Event Details Screen**: Display full description, location, and organizer details.
- [ ] **Organizer Attribution**: Distinguish between Vilvia-organized, community, and external events.

### 3. Community (Scale & Safety)
- [ ] **Pagination**: Implement cursor-based pagination for `GET /posts` and `GET /reports`.
- [ ] **Content Ownership**: Allow users to delete their own Posts and Comments.

### 4. Family & Child Rights (P0)
- [ ] **Rights Content Model**: Implement neutral, source-traceable information on Socialtjänsten and Barnkonventionen.

---

## Phase 3: Content Provenance Review (P1)

*Goal: Ensure every piece of "official" information is trustworthy and attributable.*

- [ ] **Resource Source Audit**: Review all current Resources for accurate Swedish localization (where applicable).
- [ ] **Source Link Verification**: Ensure all `source_url` fields are valid and point to authoritative government/medical sites.

---

## Phase 4: Production UX Completion (P1)

*Goal: Remove "developer-only" friction and placeholders.*

- [ ] **Profile Management**: Allow users to update their first name and gender.
- [ ] **Loading/Empty States**: Unified styling for empty lists and loading transitions across all pillars.
- [ ] **Error Handling**: Replace raw API errors with user-friendly, localized messages.

---

## Phase 5: Android Production Readiness (P0)

*Goal: Satisfy all Google Play Store technical requirements.*

- [ ] **Production Assets**: Replace icons and splash screens with final Vilvia branding.
- [ ] **Application ID Finalization**: Update `com.vilvia.vilvia` to the final production identifier.
- [ ] **Privacy Policy Resource**: Host and link a public Privacy Policy (mandated by Google Play).
- [ ] **Release AAB Generation**: Verify signed production bundle generation.

---

## Phase 6: iOS Production Readiness (P0)

*Goal: Initialize and configure the iOS platform target.*

- [ ] **iOS Initialization**: Create `ios/` directory and configure basic runner.
- [ ] **Bundle ID & Signing**: Configure App Store Connect identifiers and signing.
- [ ] **Permissions & Info.plist**: Define privacy descriptions for Internet/Storage.
- [ ] **Launch Screen & Icons**: Configure iOS-specific branding assets.

---

## Phase 7: Production Backend & Deployment (P0)

*Goal: Transition from local development to a stable production environment.*

- [ ] **Production Hosting**: Deploy FastAPI to a stable HTTPS environment (e.g., Fly.io, AWS).
- [ ] **Secrets Management**: Secure propagation of production database and Supabase keys.
- [ ] **CORS Finalization**: Lock down origins to the production domain.

---

## Phase 8: Release Validation (P0)

*Goal: Final verification before first public user.*

- [ ] **Smoke Test Suite**: Manual verification of fresh signup -> use app -> delete account on physical Android and iPhone.
- [ ] **Security Review**: Final check of authorization boundaries and rate limits.

---

## Phase 9: Store Release (EXTERNAL)

- [ ] **Google Play Console**: Listing, screenshots, Data Safety, and Deletion URL configuration.
- [ ] **App Store Connect**: Listing, screenshots, and privacy disclosures.

---

## Prioritization Summary

| Item | Priority | Status |
| :--- | :--- | :--- |
| **Fix Registration & Bootstrap** | P0 | TODO |
| **Password Reset Flow** | P0 | TODO |
| **Finalize Android Identity & Assets** | P0 | TODO |
| **Privacy Policy Resource** | P0 | TODO |
| **iOS Initialization** | P0 | TODO |
| **Rights & Benefits Content** | P1 | TODO |
| **Community Pagination** | P1 | TODO |

**Next Recommended Issue**: "Phase 1: Fix registration and first-login profile bootstrap"

---

## Definition of Done (DoD)

An Issue is complete only when:
1.  **End-to-End**: Data, Backend, and Flutter client are all updated.
2.  **Safety**: Authorization is enforced server-side; input is validated.
3.  **UX**: Loading, error, and empty states are handled gracefully.
4.  **Verification**: Automated tests pass; physical device smoke test is performed.
5.  **Documentation**: Relevant `docs/` and code comments are updated.

---

## Post-Launch Backlog (P2)

- Social Login (Google/Apple).
- AI-assisted moderation/information suggestions.
- Interactive parenting stage personalization.
- Multi-language support.
