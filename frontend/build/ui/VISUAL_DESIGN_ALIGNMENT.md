# FastStart UI - Visual Design Alignment

## Overview

This document records the visual design system implemented to match the requirement screenshots exactly. All UI components have been updated to align with the provided design specifications.

## Design System

### Color Palette

**Single teal only: `#003A46` (no other shades of green/blue).**

**Primary / Accent:**
- Sidebar, active, links, buttons, approved, caseworker, manager: `#003A46`
- Light tint for backgrounds: `#e6ecee` (e.g. teal-light, green-light, blue-light)

**Status Colors (non-teal):**
- Declined: `#f44336` (red)
- Pending: `#ffc107` (yellow)
- Escalated: `#ff9800` (orange)
- Urgent: `#f44336` (red)
- High: `#ff9800` (orange)
- Standard/Low: `#607d8b` (grey)
- Admin role: `#8a2be2` (purple)

**Backgrounds:**
- Main: `#f7f7f7`
- Panel: `#ffffff`
- Teal tint: `#e6ecee`
- Red/Orange/Purple highlights unchanged

### Layout Structure

**Sidebar:**
- Width: 256px (`w-64`)
- Background: `#003A46`
- Active state: `#003A46` with white text
- User profile section at top
- Navigation items with icons
- Notification badges: Red circles with white numbers
- Sign out button at bottom

**Main Content:**
- Background: Light grey (`#f7f7f7`)
- Padding: 24px (`p-6`)
- Cards: White background, rounded corners (8px), subtle shadow

### Typography

- Page titles: 3xl (30px), bold, teal color
- Section titles: xl (20px), bold, teal color
- Body text: base (16px), dark grey (`#212121`)
- Muted text: small (14px), medium grey (`#757575`)

### Component Specifications

**Status Chips:**
- Pill-shaped (rounded-full)
- Colored backgrounds matching status
- Bold text
- Sizes: xs, sm, md

**Buttons:**
- Primary / Success: `#003A46` (single teal only)
- Danger: Red (`#f44336`)
- Warning: Orange (`#ff9800`)
- Secondary: Outlined with border

**Tables:**
- Header: Light grey background (`bg-gray-50`)
- Rows: White background, hover state
- Borders: Light grey separators
- Padding: Consistent 12px vertical, 16px horizontal

## Screen-by-Screen Alignment

### 1. Login Page
- ✅ Dark teal header (#003A46) with VERSION 1 logo (`public/version1-logo.svg`)
- ✅ Light grey main background
- ✅ SSO button (teal #003A46)
- ✅ User selection cards for simulation
- ✅ Footer links

### 2. Dashboard/Homepage
- ✅ 4 summary cards in a row
- ✅ Colored left borders on cards
- ✅ Icons in circular backgrounds
- ✅ Large numbers, labels above
- ✅ Case Status Distribution section
- ✅ Priority Distribution section

### 3. Case Management
- ✅ Search bar with "All Cases" placeholder
- ✅ Filters button (teal)
- ✅ Table with all required columns
- ✅ Status chips (colored pills)
- ✅ Priority text (colored)
- ✅ AI Confidence (red for low, teal #003A46 for moderate/high)
- ✅ Pagination controls

### 4. Case Detail
- ✅ Back link (teal)
- ✅ Case ID (large, teal)
- ✅ Status chips next to case ID
- ✅ Case Status panel (red for declined)
- ✅ Applicant Information panel
- ✅ Documents section
- ✅ AI Analysis section
- ✅ AI Recommendation panel (right side)
- ✅ Decision Actions panel

### 5. Decision Panel
- ✅ Vertical button layout
- ✅ Approve (teal #003A46), Decline (red), Escalate (orange)
- ✅ Email Applicant (outlined)
- ✅ Modal for confirmation
- ✅ Warning banner (yellow)
- ✅ AI Recommendation display
- ✅ Confirmation checkbox

### 6. Notifications
- ✅ Filter tabs (All, Unread, etc.)
- ✅ Colored notification cards
- ✅ Left border accent
- ✅ Mark as read / Delete actions
- ✅ Unread badges

### 7. Escalated Cases
- ✅ Summary cards (4 cards)
- ✅ Colored top borders
- ✅ Detailed escalation view
- ✅ URGENT tag (red)
- ✅ SLA warning (orange)
- ✅ Action buttons (Review Case, Reassign)

### 8. User Management
- ✅ Summary cards (Total, Caseworkers, Managers, Admins)
- ✅ Create New User button (teal #003A46)
- ✅ User table with checkboxes
- ✅ Role chips (colored)
- ✅ Status chips
- ✅ Actions dropdown

### 9. Policy Management
- ✅ Info banner (teal tint)
- ✅ Upload New Policy button (teal #003A46)
- ✅ Policy cards (3 columns)
- ✅ Status tags (active)
- ✅ Category tags (purple)
- ✅ Action buttons (View, Download, Delete)

### 10. Settings
- ✅ Profile section
- ✅ Notification toggles
- ✅ Display options
- ✅ FAQ & Support links
- ✅ AI Guide section

## Implementation Notes

- All colors defined in `tailwind.config.ts` under `fast` namespace
- Global styles in `styles/globals.css`
- Light theme applied by default (`html.light` class)
- Components use Tailwind utility classes
- Status chips use reusable `StatusChip` component
- Buttons use `Button` component with variants

## Files Updated

1. `styles/globals.css` - Color variables and base styles
2. `tailwind.config.ts` - Color palette and design tokens
3. `app/(dashboard)/layout.tsx` - Sidebar with user profile and navigation
4. `app/(dashboard)/dashboard/page.tsx` - Dashboard with summary cards
5. `app/(dashboard)/cases/page.tsx` - Case management table
6. `app/(dashboard)/cases/[id]/page.tsx` - Case detail view
7. `app/(dashboard)/notifications/page.tsx` - Notifications with filters
8. `app/(dashboard)/escalated/page.tsx` - Escalated cases view
9. `app/(dashboard)/settings/page.tsx` - Settings page
10. `app/(dashboard)/admin/users/page.tsx` - User management
11. `app/(dashboard)/admin/policies/page.tsx` - Policy management
12. `app/(auth)/login/page.tsx` - Login page
13. `components/cases/DecisionPanel.tsx` - Decision actions panel
14. `components/ui/Button.tsx` - Button component
15. `components/ui/StatusChip.tsx` - Status chip component
16. `types/index.ts` - Updated types for UI data

## Verification

When running `npm run dev` in `build/ui`, the UI should visually match the requirement screenshots:
- Light grey background
- Dark teal sidebar (#003A46)
- White cards with shadows
- Single teal accent (#003A46) throughout
- Proper status colors
- Correct spacing and typography
