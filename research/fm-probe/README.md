# On-device model probe (Apple Foundation Models, macOS 27 / Xcode 27, 2026-08-23)

Question: can the on-device model classify a user's artists well enough to sort Liked Songs without a server?

`swiftc -O -parse-as-library probe.swift -o probe && ./probe artists.json` — 50 artists from a real library (25 international, 25 Israeli). Raw output in `probe.out`.

Result (~1 s/artist):
- International mainstream: ~18/25 correct, confidence 85–95.
- Israeli: ~3/25. Confidently wrong, not "unknown": Ehud Banai → hip-hop 2010s (conf 90); Hadag Nahash, Osher Cohen, Yoni Bloch → psytrance; CKay (Nigeria), Alle Farben (Germany) → Israel.

Decision: hybrid. (1) shipped curated artist table, (2) on-device only for Latin-script artists with confidence ≥ 85, (3) batched cloud fallback for the rest (~1–3 ¢ per library).
