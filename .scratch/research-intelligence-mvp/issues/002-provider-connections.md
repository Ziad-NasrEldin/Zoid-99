Status: ready-for-human

# Add external-provider connection screens

Add connection and disconnection UI only for external research providers.
Zoid 99 remains private and single-user, with no app login, signup, account creation, or app-account system.
Show prerequisites, credential location, permission scope, health, and repair action for YouTube, Meta, X, Google Trends, and the AI provider.
Never imply successful access before a provider verifies it.

Implementation evidence: native provider catalog, local preference and server-secret boundaries, connector validation seams, secure setup sheets, and fixture coverage are included in the issue 002/006 delivery commit.
Live credential proof remains intentionally outside the normal suite and must use each connector's explicit opt-in validation.
No YouTube, owned YouTube OAuth/comments, Google Trends alpha, X, Instagram/Meta, AI, or production-backend credentials were available during release 0.2.0 validation.
