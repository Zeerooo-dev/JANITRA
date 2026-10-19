# JANITRA design decisions

Build 8 direction: supplied JANITRA polished native workforce layouts. ENERGY 1 / RHYTHM 2 / MOTION 1. Navy actions, white cards and 20px gutters follow the final reference CSS; Roboto follows the app handoff. Cards group one task/person/form, semantic badges pair text with icons, and real initial avatars replace unavailable sample profile photos. The build 8 review supersedes historical layout/count/navigation notes below.

Reading this as an Android workforce login for older personnel, using the supplied JANITRA navy and plain form layout. ENERGY 1 / RHYTHM 1 / MOTION 1.

- Navy `#234E70`: supplied identity; reserved for primary actions.
- Canvas `#F5F6F8` and white inputs: supplied surfaces distinguish controls without decoration.
- Text `#202C39` and secondary `#526070`: supplied palette; measured contrast on the canvas is 13.11:1 and 5.95:1. White on navy is 8.77:1.
- Roboto: specified in the application handoff and familiar on Android; no remote font dependency in the Flutter application.
- Vertical form, 24px gutters, and scrolling: preserve the login hierarchy and keep controls reachable with large text and the keyboard.
- Permanent field labels and 56dp primary actions: match the supplied accessibility requirements.
- Password visibility icon: directly represents the visibility action and has a text tooltip.
- Dashboard counts come from complete, RLS-filtered client/workplace responses; task statistics are not shown because task APIs are unfinished. Equal count cards compare the two organization levels and stack on narrow or large-text screens.
- Native Home, Workplaces, and Profile tabs follow the supplied role separation. Edit, refresh, company, and person icons represent their named actions and retain tooltips.
- Organization lists and name dialogs use the existing 24px spacing, permanent labels, native focus feedback, and 48dp/56dp targets. Navy marks the primary create/save action; counts and the greeting establish the Home focal point.
- Light presentation: matches the approved JANITRA designs; no new theme or visual assets were introduced.

The imported HTML prototypes preserve their supplied appearance. Functional corrections do not silently replace the approved designs.
