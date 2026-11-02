# Pesto Roadmap

What is planned for Pesto, grouped into **Now**, **Next** and **Later**. For shipped releases, see the [changelog](https://copypesto.net/releases/).

---

## Now: multi-device sync

- **End-to-end encrypted multi-device Mac sync.** Built ([ADR 0018](decisions/0018-multi-device-sync.md)): off until you turn it on, per Mac, through encrypted files in iCloud Drive, with no Pesto server. Merged on main, awaiting release after the two-Mac check.

## Next: distribution and everyday use

- **Additional clipboard importers.** Expanding Settings → Data → Import to cover more macOS clipboard managers alongside the 11 already supported.
- **Sync performance and compaction tuning.** Bulk-apply path for large initial receives, and tuning the compaction threshold based on two-Mac latency numbers.

## Later: under consideration

- **Desktop widgets.** A macOS WidgetKit extension showing recent non-sensitive clips while respecting the History Lock and secret masking rules.
- **Expanded smart collection rules.** More rules for smart collections, evaluated on your Mac.
